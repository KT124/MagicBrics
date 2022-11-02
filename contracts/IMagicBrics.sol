// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.8.7;

interface IMagicBrics{

        struct Plot{
        uint256 plotNumber;
        uint256 totalsqmArea;
        uint256 askingPrice;
        string location;
        address owner;
        address realtor;
        address buyer;
        bool isForSale;
        bool isSold;
        bool offerMade;
        bool offerAccepted;



    }


        struct Deposits{
        uint256 sellerDeposit;
        uint256 buyerDeposit;
        uint256 realtorCommission;
        uint256 sellerPenalty;
    }

    struct MarketParticipants{
        bool isOwner;
        bool isRealtor;
    }



    event PlotListed(address indexed seller, address indexed realtor, uint256 indexed askingPrice, uint256 plotNumber);
    event PlotSold(address indexed buyer, uint256 indexed plotNumber);
    event PlotSaleRevoked(address indexed seller, uint256 plotNumber);
    event BuyOfferMade(address indexed buyer, uint256 indexed plotNumber, uint256 indexed offerAmount);
    event registeredAs(address indexed registered, string indexed registeredAs);
    event ethWithdrawal(address indexed receiver, uint256 indexed value);


    function REALTOR_ROLE() external view returns(bytes32);
    function SELLER_ROLE() external view returns(bytes32);
    
    // function listingDepoitAmount() external view returns(uint256);
    // function changeListingDepositAmount() external;

    function totalContractBalance() external view returns(uint256);
    function totalPlotsListed() external view returns(uint256);
    function totalPlotsSold() external view returns(uint256);

    function registerOnPlatFormAsRealtor() external;

    function registerPropertyOnPlatformAsOwner(uint256 _plotNumber) external;

    function listPlot(uint256 _plotNumber, uint256 _totalArea, uint256 _askingPrice, string memory _location, address _owner) external payable returns(uint256);
    function revokeListing(uint256 _plotNumber) external;
    function makeBuyOffer(uint256 _plotNumber) external payable;

    function sellerAcceptOffer(uint256 _plotNumber) external;

    function revokeBuyOffer(uint256 _plotNumber) external;

    // function withDraw() external;

     

}