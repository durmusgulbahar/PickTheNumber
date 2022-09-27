// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 *      -PickTheNumber bir şans oyunu. Kullanıcılar oyuna katılırken bir sayı seçer, giriş ücretini
 * öder. Oyuncular, Sayı => Seçen Kullanıcılar şeklinde bir yapıda saklanır. Ayrıca katılan oyuncuların
 * tutulduğu bir liste vardır.
 *      -Oyun maximum kullanıcıya ulaşınca oyun otomatik olarak başlar. CHainlink'ten rastgele bir sayı
 * alır ve bize 77 digitlik bir uint256 sayı verir. Bunun ilk basamağı bizim şanslı ve kazanan sayımız
 * olacaktır.
 *      -Katılan oyuncular maksimum sayıya ulaştığında oyun otomatikman başlar
 *      -Contract Chainlink coordinator'una istek atacağı için her zaman LINK bulunmalıdır.
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

/**
 *  **** Fonskyionların public/private ları ayarlanacak, 
 *  **** Contract ikinci oyuncuyu kabul etmiyor
 *  **** Eğer kimse kazanamazsa bir sistem kur
 *  **** 
 */
contract PickTheNumber is VRFConsumerBase {
    //Chainlink değişkenleri
    uint256 public vrf_fee = 0.005 ether; //VRF Coordinatorüne gönderdiğimiz ücret.
    bytes32 public keyHash; //Coordinator ve aramızda yapılan bağıntı.

    uint public _entryFee = 0.005 ether; // Oyuncular oyuna katılmak için ödemeliler.

    mapping(uint256 => Game) public games; // Game değişkenlerini tutan mapping.

    uint256[] keysOfGames; // Arayüzde kolayca "games" mapping değişkenlerini çekebilmek için
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
    uint8 public constant maxPlayers = 2;


    // 1 => [0x1, 0x2 ,0x3] böylece bir sayı kazandığında
    // bu addreslerin hepsine ödül göndericez.
    // winnersı buradan çekicez.
    mapping(uint => address[]) public playersAndSelectedNumbers; // 0-9 olan sayıları seçen address listeleri

    
    constructor(
        address _vrfCoordinator,
        address linkToken,
        
        bytes32 _keyHash
    ) VRFConsumerBase(_vrfCoordinator, linkToken) {
        
        keyHash = _keyHash;
        isGameStarted = false;
    }

    struct Game {
        uint gameID; // Her oyunun özel ID'si var. Bu gameCounter ile belirleniyor.
        uint luckyNumber; // Rastgele seçilen 16 rakam.
        address[] participants; // Oyun katılımcıları, oyun bittiğinde atanır ve depolanır. Max 20 kişi.
        uint totalReward; // Oyunun ödül havuzu
        address[] winners; // Oyunun kazananları
    }

    event EnterTheGame(uint indexed gameID, address participant);

    event GameStart(uint indexed gameID);

    event GameEnd(uint indexed gameID, uint luckyNumber, address[] winners);

    event PickedTheNumber(uint indexed gameID, address player, uint number);

    //HAZIRLIK EVRESİ
    /** 
    @dev Kullanıcı, entryFee yi öder ve bir sayı seçerek oyuna giriş yapar.
    */
    function enterGame(uint _selectedNumber) external payable {
        require(!isGameStarted, "Game is not started yet");
        require(gameParticipants.length < maxPlayers, "Game is full");
        require(msg.value == _entryFee, "Entry fee is 0.005 Ether !");

        gameParticipants.push(msg.sender);

        gameParticipantsCounter++;

        playersAndSelectedNumbers[_selectedNumber].push(msg.sender);

        emit PickedTheNumber(gameCounter, msg.sender, _selectedNumber);

        emit EnterTheGame(gameCounter, msg.sender);

        if (gameParticipants.length == maxPlayers) {
            startGame();
        }
    }

    //OYUN

    /*
    @dev Oyunu başlatır. İlk olarak Chainlink aracılığıyla 0-15 arasında 16 tane numara rastgele olarak seçilir.
         Bu rastgele üretilen sayılardan en fazla tekrar edeni bulunur.

    */

    function startGame() public {
        isGameStarted = true;

        emit GameStart(gameCounter);

        getLuckyNumberFromChainlink();
    }

    function getLuckyNumberFromChainlink() public returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= vrf_fee, "Not enough LINK");
        return requestRandomness(keyHash, vrf_fee);
    }

    //OYNANIŞ PİPELİNE
    /**
     * @dev randomness bize 77 digitlik bir random uin256 sayısı veriyor. Biz bunun ilk 16 basamağını alacağız.
     * @dev override fonksiyon
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        virtual
        override
    {
        uint256 winnerNumber = randomness / 10**76; // İlk digitni aldık.
        luckyNumber = winnerNumber;
        setWinners(winnerNumber);
    }

    /**
     * @dev Winner Number'ı seçenleri winner listesine atıyoruz.
     */
    function setWinners(uint _winnerNumber) public {
        winners = playersAndSelectedNumbers[_winnerNumber];

        sendRewards();
    }

    /**
     * @dev Ödül havuzunu kazanan liste uzunluğuna bölüyoruz ve kişi başı kazanılan ödülü hesaplıyoruz
     * winner listesinde olan her kişiye sıra sıra bu ödülü gönderiyoruz.
     */
    function sendRewards() internal {
        uint rewardForEach = totalReward / winners.length;

        for (uint i = 0; i < winners.length; i++) {
            (bool sent, ) = winners[i].call{value: rewardForEach}("");
            require(sent, "Failed to send reward");
        }

        finishTheGameAndStoreGameData();
    }

    //BİTİŞ
    function finishTheGameAndStoreGameData() private {
        Game memory finishedGame = Game({ //GAME STRUCT kayıt olarak kullanılacak. Oyun bittikten sonra oluşturulacak.
            gameID: gameCounter,
            luckyNumber: luckyNumber,
            participants: gameParticipants, //Get participants from function as array
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
     * @dev Reset the game and ready to start new game.
     */
    function beReadyToNewGame() internal {
        for (uint i = 0; i < gameParticipantsCounter; i++) {
            delete gameParticipants[i];
        }

        delete gameParticipants; //Katılımcıların listesi
        delete gameParticipantsCounter; //Katılımcı sayısı
        delete luckyNumber; // 0-9 arası rastegele seçilmiş rastgele bir sayı
        delete winners; // Girişte en çok tekrar eden sayıyı bulanlar
        delete totalReward; // Oynanmakta olan oyunun ödül havuzu
        delete isGameStarted;
        isGameStarted = false;
    }

    /*
    @@@@@ GETTERS
    */

    function getTotalReward() public view returns (uint) {
        return getPlayerList().length * _entryFee;
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

    function getLinkBalance() public view returns (uint){
        return LINK.balanceOf(address(this));
    }

    receive() external payable {}

    fallback() external payable {}
}
