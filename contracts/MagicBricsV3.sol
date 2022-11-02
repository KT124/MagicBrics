// SPDX-License-Identifier: GPL-3.0

/// @title MagicBrics
/// @author Manish
/// @notice For selling and buying plots

/// @notice seller pays commission of 1% if withdraws , seller pays 2% if deposit penalty if withdraws sale after accepting offer
/// @notice buyer pays commission of 1% if sale successful

pragma solidity =0.8.7;

import {IMagicBrics} from "./IMagicBrics.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MagicBrics is IMagicBrics, ReentrancyGuard, AccessControl {
    bytes32 public constant override SELLER_ROLE = keccak256("SELLER_ROLE");
    bytes32 public constant override REALTOR_ROLE = keccak256("REALTOR_ROLE");

    error IncorrectAdvance(uint256 value, string message);

    uint256 public override totalPlotsListed;
    uint256 public override totalPlotsSold;
    uint256 public override totalContractBalance;

    mapping(uint256 => Plot) public indexToPlot;
    mapping(uint256 => address) public propertyIdToOwner;
    mapping(address => MarketParticipants) isRegisteredAs;
    mapping(uint256 => address) realtorOfPlot;
    mapping(address => uint256) advanceDeposited;
    mapping(uint256 => mapping(address => Deposits)) plotIdToDeposits;
    mapping(address => mapping(uint256 => bool)) isBuyerOf;
    mapping(uint256 => bool) plotSaleCancelled;
    mapping(uint256 => bool) buyOfferRevoked;
    mapping(uint256 => uint256) coolingPeriod;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(REALTOR_ROLE, msg.sender);
        _grantRole(SELLER_ROLE, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
    }

    function listPlot(
        uint256 _plotNumber,
        uint256 _totalArea,
        uint256 _askingPrice,
        string memory _location,
        address _owner
    ) public payable override returns (uint256 _plotIndex) {
        require(
            hasRole(REALTOR_ROLE, msg.sender),
            "Market: only registered realtors!"
        );

        require(
            !indexToPlot[_plotNumber].isForSale,
            "Market: alredy for sale!"
        );

        require(
            _owner == propertyIdToOwner[_plotNumber],
            "Market: register property on platfrom!"
        );

        // calculating pentality to be deposited when listing. This is used to pay buyer if seller withdraws
        // after taking advance. this pay is 2 percent of deposit, which is in turn 10% of asking price
        // if seller does not withdraws sale after taking advance he will able to withdraw it
        // uint256 _commission = (1 * _askingPrice) / 100;
        uint256 _expectedAdvancedDepostit = (10 * _askingPrice) / 100;
        uint256 _penanlty = (2 * _expectedAdvancedDepostit) / 100;

        require(
            msg.value > 0 && msg.value >= _penanlty,
            "Market: send right listingFee!"
        );

        // storing penalty to return to seller if he does not withdraws sale after accepting it

        plotIdToDeposits[_plotNumber][propertyIdToOwner[_plotNumber]]
            .sellerPenalty = _penanlty;

        realtorOfPlot[_plotNumber] = msg.sender;

        // storing _commission from seller side
        // plotIdToDeposits[_plotNumber][msg.sender].realtorCommission += _commission;

        unchecked {
            totalPlotsListed++;
        }

        indexToPlot[_plotNumber] = Plot({
            plotNumber: _plotNumber,
            totalsqmArea: _totalArea,
            askingPrice: _askingPrice,
            location: _location,
            owner: _owner,
            realtor: msg.sender,
            buyer: address(0),
            isForSale: true,
            isSold: false,
            offerMade: false,
            offerAccepted: false
        });

        totalContractBalance += msg.value;

        emit PlotListed(_owner, msg.sender, _askingPrice, _plotNumber);

        return totalPlotsListed;
    }

    function registerPropertyOnPlatformAsOwner(uint256 _plotNumber)
        external
        override
    {
        require(
            hasRole(SELLER_ROLE, msg.sender),
            "MagicBrics: get authorization by admin first!"
        );

        propertyIdToOwner[_plotNumber] = msg.sender;

        emit registeredAs(msg.sender, "Property Owner");
    }

    function registerOnPlatFormAsRealtor() external override {
        require(
            hasRole(REALTOR_ROLE, msg.sender),
            "MagicBrics: get authorization by admin first!"
        );

        isRegisteredAs[msg.sender] = MarketParticipants({
            isOwner: false,
            isRealtor: true
        });

        emit registeredAs(msg.sender, "Realtor");
    }

    function makeBuyOffer(uint256 _plotNumber) external payable override {
        require(indexToPlot[_plotNumber].isForSale, "Market: not for sale!");
        require(!indexToPlot[_plotNumber].isSold, "Market: already sold!");
        require(
            msg.sender != indexToPlot[_plotNumber].owner,
            "Market: property owner not allowed!"
        );

        require(
            !indexToPlot[_plotNumber].offerAccepted,
            "Market: owner already accepted an offer!"
        );
        require(
            indexToPlot[_plotNumber].buyer != msg.sender,
            "Market: only one offer per person!"
        );

        uint256 minDeposit = (10 * indexToPlot[_plotNumber].askingPrice) / 100;

        uint256 _sentValue = msg.value;

        require(_sentValue >= minDeposit, "Market: send >= min Deposit");

        //to track deplosited advance by buyers
        advanceDeposited[msg.sender] += _sentValue;

        // used to deduct 10% penalty if buyer withdraws his offer. used in withdrawEth function later to allow buyer to withdraw;

        plotIdToDeposits[_plotNumber][msg.sender].buyerDeposit = _sentValue;

        indexToPlot[_plotNumber].buyer = msg.sender;
        indexToPlot[_plotNumber].offerMade = true;
        isBuyerOf[msg.sender][_plotNumber] = true;

        totalContractBalance += msg.value;

        emit BuyOfferMade(msg.sender, _plotNumber, _sentValue);
    }

    function revokeBuyOffer(uint256 _plotNumber) external override {
        require(indexToPlot[_plotNumber].isForSale, "Market: not for sale!");
        require(
            msg.sender == indexToPlot[_plotNumber].buyer,
            "Market: no offer by you!"
        );
        require(!indexToPlot[_plotNumber].isSold, "Market: already sold!");

        /** @dev 10 % penalty imposed due to withdrawing buy offer after 14 days*/

        uint256 _penalty = ((10 *
            plotIdToDeposits[_plotNumber][msg.sender].buyerDeposit) / 100);

        plotIdToDeposits[_plotNumber][msg.sender].buyerDeposit -= _penalty;

        delete indexToPlot[_plotNumber].buyer;
        delete indexToPlot[_plotNumber].offerMade;

        buyOfferRevoked[_plotNumber] = true;
    }

    function sellerAcceptOffer(uint256 _plotNumber) external override {
        require(
            msg.sender == indexToPlot[_plotNumber].owner,
            "Market: only owner!"
        );
        require(
            indexToPlot[_plotNumber].isForSale,
            "Market: input correct plot number!"
        );
        require(
            indexToPlot[_plotNumber].offerMade,
            "Market: no buy offer yet!"
        );
        require(
            !indexToPlot[_plotNumber].offerAccepted,
            "Market: already accepted!"
        );
        indexToPlot[_plotNumber].offerAccepted = true;
    }

    function depositRemainingAmountAndConcludeSale(uint256 _plotNumber)
        external
        payable
    {
        require(
            msg.sender == indexToPlot[_plotNumber].buyer,
            "Market: no offer made by you!"
        );
        require(
            !indexToPlot[_plotNumber].isSold,
            "MagicBrics: deposit complete!"
        );
        require(
            indexToPlot[_plotNumber].offerAccepted,
            "Market: offer not accepted by owner yet!"
        );

        uint256 _advanceDeposited = advanceDeposited[msg.sender];

        uint256 _remaingAmount = (indexToPlot[_plotNumber].askingPrice -
            _advanceDeposited);

        require(msg.value >= _remaingAmount, "MagicBrics: send right amount!");

        //    uint256 _plotNumber = indexToPlot[_plotNumber].plotNumber;

        address _seller = propertyIdToOwner[_plotNumber];

        plotIdToDeposits[_plotNumber][msg.sender].buyerDeposit += msg.value;

        // here the seeler dopostit is being updated first time
        plotIdToDeposits[_plotNumber][_seller]
            .sellerDeposit += plotIdToDeposits[_plotNumber][msg.sender]
            .buyerDeposit;
        //updating total contract balance
        totalContractBalance += msg.value;

        indexToPlot[_plotNumber].isSold = true;

        coolingPeriod[_plotNumber] = block.timestamp + 180 seconds;

        emit PlotSold(msg.sender, _plotNumber);
    }

    function revokeListing(uint256 _plotNumber) external override {
        require(indexToPlot[_plotNumber].isForSale, "not listed!");

        if (indexToPlot[_plotNumber].isForSale) {
            require(
                msg.sender == indexToPlot[_plotNumber].owner,
                "MagicBrics: only owner!"
            );

            uint256 buyerCompensation = plotIdToDeposits[_plotNumber][
                msg.sender
            ].sellerPenalty;

            address _buyer = indexToPlot[_plotNumber].buyer;

            // uint256 _plotNumber = indexToPlot[_plotNumber].plotNumber;
            plotIdToDeposits[_plotNumber][_buyer]
                .buyerDeposit += (buyerCompensation +
                plotIdToDeposits[_plotNumber][msg.sender].buyerDeposit);

            //updating contract balance getter

            totalContractBalance = plotIdToDeposits[_plotNumber][_buyer]
                .buyerDeposit;

            // setting withdrawable value for plot id owner to zero
            delete plotIdToDeposits[_plotNumber][msg.sender].sellerDeposit;

            //removing the plot listing info from state variable
            delete indexToPlot[_plotNumber];

            // updating plotsale cancelled state var which is  used to enable correct buyer to withdraw deposited amount

            plotSaleCancelled[_plotNumber] = true;
        } else {
            //removing the plot listing info from state variable
            delete indexToPlot[_plotNumber];

            // updating plotsale cancelled state var which is  used to enable correct buyer to withdraw deposited amount
            plotSaleCancelled[_plotNumber] = true;
        }
        // updating the totalplots listed state var
        unchecked {
            totalPlotsListed--;
        }
    }

    function sellerWithdraw(uint256 _plotNumber)
        external
        nonReentrant
        returns (bool)
    {
        // NEED TO IMPLEMENT REENTRANCEY GURAD
        require(
            hasRole(SELLER_ROLE, msg.sender),
            "MagicBrics: only authorize sellers!"
        );

        require(
            msg.sender == indexToPlot[_plotNumber].owner,
            "MagicBrics: only plot owner!"
        );
        require(
            block.timestamp > coolingPeriod[_plotNumber],
            "only after 14 days post sale!"
        );

        require(
            indexToPlot[_plotNumber].isSold,
            "MagicBrics: buyer haven't deposited the difference amount yet!"
        );

        // uint256 _plotNumber = indexToPlot[_plotNumber].plotNumber;
        address _buyer = indexToPlot[_plotNumber].buyer;

        uint256 _amount = plotIdToDeposits[_plotNumber][_buyer].buyerDeposit;

        require(_amount > 0, "Market: zero balance!");

        uint256 _commission = (1 * _amount) / 100;
        address _realtor = realtorOfPlot[_plotNumber];

        plotIdToDeposits[_plotNumber][_realtor].realtorCommission = _commission;

        uint256 _netSellerAmount = _amount - _commission;

        // TRANSFERRRING OWNERHIP OF PLOT

        propertyIdToOwner[_plotNumber] = _buyer;

        delete indexToPlot[_plotNumber];

        totalPlotsListed--;

        totalPlotsSold++;

        totalContractBalance -= _amount;

        // setting value to zero

        delete plotIdToDeposits[_plotNumber][msg.sender].sellerDeposit;

        emit ethWithdrawal(msg.sender, _amount);

        (bool success, ) = msg.sender.call{value: _netSellerAmount}("");

        require(success, "Eth TF");

        return success;
    }

    // To enable buyer to  withdraw their fund in case seller cancels sale

    function buyerWithdraw(uint256 _plotNumber)
        external
        nonReentrant
        returns (bool success)
    {
        // NEED TO IMPLEMENT REENTRANCEY GURAD

        require(msg.sender != address(0), "MagicBrics: 0x0 address!");
        require(isBuyerOf[msg.sender][_plotNumber], "only buyer!");
        require(
            plotSaleCancelled[_plotNumber] || buyOfferRevoked[_plotNumber],
            "not allowed!"
        );

        require(
            msg.sender != indexToPlot[_plotNumber].owner,
            "MagicBrics: plot owner not allowed!"
        );

        if (!buyOfferRevoked[_plotNumber]) {
            // if buyer has not take back the offer the following code executes as normal
            // else the code in 'else' block execute which deducts the penalty of 10% total amount deposited by buyer and
            uint256 _amount = plotIdToDeposits[_plotNumber][msg.sender]
                .buyerDeposit;

            plotSaleCancelled[_plotNumber] = false;
            buyOfferRevoked[_plotNumber] = false;

            require(_amount > 0, "Market: zero balance!");

            // setting value to zero before transfer of  value

            delete plotIdToDeposits[_plotNumber][msg.sender].buyerDeposit;

            totalContractBalance -= _amount;

            emit ethWithdrawal(msg.sender, _amount);

            (success, ) = msg.sender.call{value: _amount}("");

            require(success, "Eth TF");

            return success;
        } else {
            uint256 penalty = ((10 *
                plotIdToDeposits[_plotNumber][msg.sender].buyerDeposit) / 100);

            plotIdToDeposits[_plotNumber][msg.sender].buyerDeposit -= penalty;

            uint256 _amount = plotIdToDeposits[_plotNumber][msg.sender]
                .buyerDeposit;

            delete plotIdToDeposits[_plotNumber][propertyIdToOwner[_plotNumber]]
                .sellerPenalty;

            plotSaleCancelled[_plotNumber] = false;
            buyOfferRevoked[_plotNumber] = false;

            require(_amount > 0, "Market: zero balance!");

            totalContractBalance -= _amount;

            // setting value to zero before transfer of value

            delete plotIdToDeposits[_plotNumber][msg.sender].buyerDeposit;

            emit ethWithdrawal(msg.sender, _amount);

            (success, ) = msg.sender.call{value: _amount}("");

            require(success, "Eth TF");

            return success;
        }
    }

    function realtorWithDraw(uint256 _plotNumber) external nonReentrant {
        require(
            msg.sender == realtorOfPlot[_plotNumber],
            "you aren't agent of this plot!"
        );
        uint256 _commission = plotIdToDeposits[_plotNumber][msg.sender]
            .realtorCommission;

        require(_commission > 0, "0 balance!");

        // totalContractBalance = (totalContractBalance - _commission);

        // deleting the commission mapping for plot number
        delete plotIdToDeposits[_plotNumber][msg.sender].realtorCommission;
        delete realtorOfPlot[_plotNumber];

        emit ethWithdrawal(msg.sender, _commission);

        (bool success, ) = msg.sender.call{value: _commission}("");

        require(success, "Eth TF");
    }

    function realtorBalance(uint256 _plotNumber)
        external
        view
        returns (uint256 _realtorBalance)
    {
        require(hasRole(REALTOR_ROLE, msg.sender), "only realtors!");
        return plotIdToDeposits[_plotNumber][msg.sender].realtorCommission;
    }

    function sellerBalance(uint256 _plotNumber)
        external
        view
        returns (uint256)
    {
        uint256 _balance = plotIdToDeposits[_plotNumber][msg.sender]
            .sellerDeposit;

        return _balance;
    }

    function buyerBalance(uint256 _plotNumber) external view returns (uint256) {
        uint256 _balance = plotIdToDeposits[_plotNumber][msg.sender]
            .buyerDeposit;

        return _balance;
    }

    function contracBalanceWithDraw()
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 _value = address(this).balance;

        totalContractBalance -= _value;
        require(_value > 0, "0 balance!");

        emit ethWithdrawal(msg.sender, address(this).balance);

        (bool success, ) = msg.sender.call{value: _value}("");

        require(success, "Eth TF");
    }

    function sellerPenalty(uint256 _plotNumber)
        external
        view
        returns (uint256 _penalty)
    {
        return plotIdToDeposits[_plotNumber][msg.sender].sellerPenalty;
    }

    function whoosh() external {
        selfdestruct(payable(msg.sender));
    }
}
