// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;


contract PickTheNumber {
    
    uint public _entryFee = 0.005 ether; // Users has to pay to enter a game.

    mapping(address => PlayerInfo) public users; // address => PlayerInfo
    mapping(uint256 => Game) public games; //index => Game
    
    uint256[] keysOfGames; // Key indexes of the "games" mapping.



    struct Game{
        uint gameID;         // Each game has unique ID
        uint[] luckyNumbers; // Randomly selected 16 pcs numbers.
        uint startAt;        // The time is game started.
        uint endAt;          // The time is game ended.
        address[] participants; // Participants of the game.
        uint totalReward;    // Total reward of the game.
        address[] winners;      // Winners of the game.

    }

    struct PlayerInfo{
        uint totalPlayedBalance;
        uint totalNumberOfGameEntered;
        uint totalNumberOfGameWon;
        uint totalAmountOfRewardWon;
    }

    

    event EnterTheGame(
        uint gameID,
        uint startAt
    );

    event GameStart(
        uint gameID,
        uint startAt
    );

    event GameEnd(
        uint gameID,
        uint[] luckyNumbers,
        address[] winners
    );




    


    //generate random number function
    //start the game function
    //enter the game function
    //ended the game func 
    //send money to the winners func
    //calculate the reward for each winner
    //owner collect fees function
    
}