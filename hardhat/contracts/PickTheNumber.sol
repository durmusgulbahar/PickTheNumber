// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

/**
 *      -PickTheNumber bir şans oyunu. Kullanıcılar oyuna katılırken bir sayı seçer, giriş ücretini
 * öder. Oyuncular, Sayı => Seçen Kullanıcılar şeklinde bir yapıda saklanır. Ayrıca katılan oyuncuların
 * tutulduğu bir liste vardır.
 *      -Oyun maximum kullanıcıya ulaşınca oyun otomatik olarak başlar. CHainlink'ten rastgele bir sayı
 * alır ve bize 77 digitlik bir uint256 sayı verir. Bunun ilk basamağı bizim şanslı ve kazanan sayımız
 * olacaktır.
 *      -Katılan oyuncular maksimum sayıya ulaştığında oyun otomatikman başlar
 *      -Kontrat vrf.chainlink tarafından kullanılıyor. Chainlink VRF2 kullanımı :
 *          --Chainlink VRF2 bir hesabın açtığı fund ile o fund'un subscription ID'sini kullanan
 *          --kontratlara LINK gönderiyor. Böylece kontratın LINK depolama zorunluluğu kalkmış oluyor.
 *          --ve her işlemde LINK göndermediği için tasarruf sağlanıyor.
 *      -Kazanan sayı belirlendiği zaman oyuncu listesini mapping sayesinde alabilirz.
 *      -Bir döngü yardımıyla kazananlar listesine sırayla hesaplanmış ödüller gönderilir.
 *      -Kişi başı ödül -> (maxPlayer * entryFee) / (winner.length) olarak hesaplanır.
 *      -Oyun bittiğinde ve ödüller dağıtıldığında oynanan oyunun bilgileri bir "games" mappingde saklanır.
 *      -Sonrasında bütün oynanan oyunun dataları sıfırlanır. Ve contract yeni oyuna hazır olur.
 *      -Olduğunca döngü kullanmamaya özen gösterdim.
 *      -Oyun pipeline şeklinde dizayn edilmiştir, her fonksiyon bir sonraki fonksiyonu çağıracaktır.
 * bu şekilde bir otomasyon yakalanma amaçlanmıştır.
 *
 */

contract PickTheNumber is VRFConsumerBaseV2, ConfirmedOwner {
    // @@@@@Chainlink değişkenleri
    // The gas lane to use, which specifies the maximum gas price to bump to.
    // For a list of available gas lanes on each network,
    // see https://docs.chain.link/docs/vrf/v2/subscription/supported-networks/#configurations
    bytes32 keyHash =
        0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 100,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 callbackGasLimit = 100000;

    // The default is 3, but you can set this higher.
    uint16 requestConfirmations = 3;

    // 1 Adet random sayı döndürüyor.
    uint32 numWords = 1;

    uint64 s_subscriptionId; // Subscription ID.

    VRFCoordinatorV2Interface COORDINATOR;

    uint public _entryFee = 0.005 ether; // Oyuncular oyuna katılmak için ödemeliler.

    mapping(uint256 => Game) public games; // Game değişkenlerini tutan mapping.

    uint256[] public keysOfGames; // Arayüzde kolayca "games" mapping değişkenlerini çekebilmek için
    // keylerini burada listeliyoruz böylece kolayca bir döngüyle Game verilerini çekebileceğiz.

    uint256 private gameCounter = 1; // gameCounter, her Game değişkeninin gameID'sine eşittir
    // Her oyun bittiğinde gameCounter +1 artar.
    // Toplam kaç oyun oynandığın gösterir.

    //Hali hazırda Oynanan oyunun verileri, bunlar oyun bittikten sonra "Game" değişkenine atanıp
    // "games" mappinginde depolanacak ve sonrasında yeni oyun için sıfırlanacak.
    address[] public gameParticipants; //Katılımcıların listesi
    uint public gameParticipantsCounter = 0; //Katılımcı sayısı
    uint public luckyNumber; // 0-9 arası rastegele seçilmiş 16 sayı
    address[] public winners; // Girişte en çok tekrar eden sayıyı bulanlar
    uint public totalReward; // Oynanmakta olan oyunun ödül havuzu
    bool public isGameStarted;
    uint8 public constant maxPlayers = 3; // Maksimum oyuncu sayısına ulaşıldığı an oyun başlar.

    // 1 => [0x1, 0x2 ,0x3] böylece bir sayı kazandığında
    // bu addreslerin hepsine ödül göndericez.
    // winnersı buradan çekicez.
    mapping(uint => address[]) public playersAndSelectedNumbers; // 0-9 olan sayıları seçen address listeleri

    constructor(uint64 subscriptionId)
        VRFConsumerBaseV2(0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D)
        ConfirmedOwner(msg.sender)
    {
        s_subscriptionId = subscriptionId;
        COORDINATOR = VRFCoordinatorV2Interface(
            0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D
        );
        isGameStarted = false;
    }

    struct Game {
        uint gameID; // Her oyunun özel ID'si var. Bu gameCounter ile belirleniyor.
        uint luckyNumber; // Rastgele seçilen 16 rakam.
        address[] participants; // Oyun katılımcıları, oyun bittiğinde atanır ve depolanır. Max 20 kişi.
        uint totalReward; // Oyunun ödül havuzu
        address[] winners; // Oyunun kazananları
    }

    event EnterTheGame(
        uint indexed gameID,
        address participant,
        uint selectedNumber
    ); // oyuna katılış

    event GameStart(uint indexed gameID); // Oyun başlangıcı

    event GameEnd(uint indexed gameID, uint luckyNumber, address[] winners); // oyun bitişi

    event NoWinner(uint indexed gameID, uint totalReward);

    //Chainlink events
    event RequestSent(uint256 requestId, uint32 numWords);

    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    //@@@@@@@@ HAZIRLIK EVRESİ

    /** 
    @dev Kullanıcı, entryFee yi öder ve bir sayı seçerek oyuna giriş yapar.
    @param _selectedNumber - Oyuncunun seçtiği sayı.
    */
    function enterGame(uint _selectedNumber) external payable {
        require(!isGameStarted, "Game is not started yet");
        require(gameParticipants.length < maxPlayers, "Game is full");
        require(msg.value == _entryFee, "Entry fee is 0.005 Ether !");

        gameParticipants.push(msg.sender);

        gameParticipantsCounter++;

        playersAndSelectedNumbers[_selectedNumber].push(msg.sender);

        emit EnterTheGame(gameCounter, msg.sender, _selectedNumber);

        if (gameParticipants.length == maxPlayers) {
            startGame();
        }
    }

    //@@@@@@@@@@@ OYUN EVRESİ

    /**
    @dev Oyunu başlatır. İlk olarak Chainlink aracılığıyla 0-15 arasında 16 tane numara rastgele olarak seçilir.
         Bu rastgele üretilen sayılardan en fazla tekrar edeni bulunur.

    */

    function startGame() public {
        isGameStarted = true;

        emit GameStart(gameCounter);

        requestRandomWords();
    }

    function requestRandomWords() internal returns (uint256 requestId) {
        // Eğer subscription ayarlanmamışsa ve bakiye yetersizse hata verir.
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        emit RequestSent(requestId, numWords);
        return requestId;
    }

    //OYNANIŞ PİPELİNE
    /**
     * @dev randomness bize 77 digitlik bir random uin256 sayısı veriyor. Biz bunun ilk 16 basamağını alacağız.
     * @dev override fonksiyon
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        uint256 winnerNumber = _randomWords[0] / 10**76; // gelen random sayının ilk digitni aldık
        luckyNumber = winnerNumber;
        emit RequestFulfilled(_requestId, _randomWords);
        setWinners(winnerNumber);
    }

    /**
     * @dev Winner Number'ı seçenleri winner listesine atıyoruz.
     */
    function setWinners(uint _winnerNumber) public {
        winners = playersAndSelectedNumbers[_winnerNumber];

        if (winners[0] == address(0)) {
            finishTheGameAndStoreGameData();
            emit NoWinner(gameCounter, getTotalReward());
            revert("Kazanan yok, kasa bir sonraki oyuna devredildi.");
        }

        sendRewards(winners);
    }

    /**
     * @dev Ödül havuzunu kazanan liste uzunluğuna bölüyoruz ve kişi başı kazanılan ödülü hesaplıyoruz
     * winner listesinde olan her kişiye sıra sıra bu ödülü gönderiyoruz.
     */
    function sendRewards(address[] memory _winners) internal {
        uint rewardForEach = getTotalReward() / _winners.length;

        for (uint i = 0; i < _winners.length; i++) {
            (bool sent, ) = _winners[i].call{value: rewardForEach}("");
            require(sent, "Failed to send reward");
        }

        finishTheGameAndStoreGameData();
    }

    /**
     * @dev Oyun biter ve oyunun verileri "games" mapping'ine kaydedilir.
     */
    function finishTheGameAndStoreGameData() private {
        Game memory finishedGame = Game({ //GAME STRUCT kayıt olarak kullanılacak. Oyun bittikten sonra oluşturulacak.
            gameID: gameCounter,
            luckyNumber: luckyNumber,
            participants: gameParticipants, // Katılımcılar
            totalReward: getTotalReward(),
            winners: winners // getWinners()
        });

        games[gameCounter] = finishedGame;
        keysOfGames.push(gameCounter);
        gameCounter++;

        emit GameEnd(gameCounter, luckyNumber, winners);

        beReadyToNewGame();
    }

    /**
     * @dev Oyun verilerini sıfırlar ve yeni oyuna hazırlık yapar.
     */
    function beReadyToNewGame() internal {
        for (uint i = 0; i < gameParticipantsCounter; i++) {
            delete gameParticipants[i];
        }

        delete gameParticipants; //Katılımcıların listesi
        delete gameParticipantsCounter; //Katılımcı sayısı
        delete luckyNumber; // 0-9 arası rastegele seçilmiş rastgele bir sayı
        delete winners; // Girişte en çok tekrar eden sayıyı bulanlar
        totalReward = address(this).balance; // Oynanmakta olan oyunun ödül havuzu
        isGameStarted = false;
    }

    /**
     * GETTERS
     * @dev Oyun verilerinin getter fonksiyonları.
     */

    function getTotalReward() public view returns (uint) {
        return address(this).balance;
    }

    function getWinners() public view returns (address[] memory) {
        return winners;
    }

    function getLuckyNumber() public view returns (uint) {
        return luckyNumber;
    }

    function getPlayerList() public view returns (address[] memory) {
        return gameParticipants;
    }

    function totalPlayersCurrentGame() public view returns (uint) {
        return gameParticipantsCounter;
    }

    receive() external payable {}

    fallback() external payable {}
}
