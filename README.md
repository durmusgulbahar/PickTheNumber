# Akbank Practicum Final Task by https://www.patika.dev/

## Created for Akbank Practicum with Hardhat

### PICK THE NUMBER GAME 

--contract address-- -> 0x939e933F267cF9b866881f9E76548F4BE0B15799

1. Oyuncu oyuna girişte bir ücret(0.005 ether) öder ve 0-9 arası bir sayı seçer. 
    - Oyuna giriş eventi tetiklenir.
2. Maksimum oyuncu sayısına ulaşıldığında otomatik olarak oyun başlar. 
    - Oyun başladı eventi tetiklenir.
3. İlk olarak Chainlink'ten rastgele bir uint256 sayı alınır.
    - RequestSent eventi tetiklenir.
4. Bu rastgele sayının ilk basamağı bizim **Şanslı Sayı**mızdır. 
5. Bu sayının belirlenmesi yaklaşık 1-1.5 dakika alıyor.
    - RequestFulfilled eventi tetiklenir.
6. Oyuncularımız ve seçtikleri sayı bir mapping'de tutulur
    > **mapping(uint -> address) playersAndSelectedNumbers** yani her sayının kendine ait bir addres listesi vardır. Bu listede
    belirtilen sayıyı seçen oyuncular bulunur. Örnek olarak :
    2 -> [0x241924129314928, 0x241924129314923] gibi.
7.  **Şanslı Sayı**mız belirlendikten sonra **playersAndSelectedNumbers** isimli mappinginden şanslı sayımızı alırız. Her sayı oyuncu listesi tuttuğu için bir for döngüsü kullanmayız. Direkt bu listeyi çekebiliriz.
8.  Kasa bakiyemiz, kazananların sayısına bölünerek kişi başı ödül hesaplanır.
9.  Bu kişi başı ödül her kazanana contract tarafından gönderilir.
10. Eğer kazanan yoksa ödül bir sonraki oyuna devreder.
11. Oyun bitişinde oyun verileri bir **Game** struct'ında tutulur ve **mapping(uint -> Game) games** isimli mappingimizde depolanır. 
12. Oyun bütün adımlar sırasıyla otomatik bir şekilde birbirini tetikleyecek şekilde dizayn edilmiştr.



by Durmuş Gülbahar / https://app.patika.dev/durmuss
