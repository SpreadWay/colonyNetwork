/*
  This file is part of The Colony Network.

  The Colony Network is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  The Colony Network is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with The Colony Network. If not, see <http://www.gnu.org/licenses/>.
*/

pragma solidity ^0.4.17;
pragma experimental "v0.5.0";
pragma experimental "ABIEncoderV2";

import "../lib/dappsys/math.sol";
import "./ColonyNetworkStorage.sol";
import "./ERC20Extended.sol";
import "./IColony.sol";


contract ColonyNetworkAuction is ColonyNetworkStorage {
  event AuctionCreated(address auction, address token, uint256 quantity, uint256 startPrice);

  function startTokenAuction(
    address _token,
    uint256 _quantity,
    uint256 _startPrice)
    public 
    {
    ERC20Extended clny = ERC20Extended(IColony(_colonies["Common Colony"]).getToken());
    DutchAuction auction = new DutchAuction(address(clny), _token, _quantity, _startPrice);
    ERC20Extended(_token).transfer(auction, _quantity);
    AuctionCreated(address(auction), _token, _quantity, _startPrice);
  }
}


// Dutch auction contract - distribution of a fixed number of tokens using an auction
// The contract code is inspired by the Raiden and Gnosis Dutch auction contracts
contract DutchAuction is DSMath {
  address public colonyNetwork;
  ERC20Extended public clnyToken;
  ERC20Extended public token;

  // Starting price in CLNY wei per Token wei
  uint public startPrice;
  uint public startBlock;
  uint public endBlock;
  // Keep track of all CLNY wei received
  uint public receivedTotal;
  // Keep track of cumulative CLNY funds for which the tokens have been claimed
  uint public tokensClaimed;
  // Total number of auctioned tokens
  uint public quantity;
  // CLNY Wei per Token wei
  uint public finalPrice;
  uint public constant MULTIPLIER = 10 ** 18;
  bool public finalized;
  
  mapping (address => uint256) public bids;

  modifier auctionNotFinalized() {
    require(!finalized);
    _;
  }

  modifier auctionFinalized {
    require(finalized);
    _;
  }

  modifier endBlockNotSet {
    require(endBlock == 0);
    _;
  }

  modifier endBlockSet {
    require(endBlock > 0);
    _;
  }

  modifier allBidsClaimed  {
    require(tokensClaimed == receivedTotal);
    _;
  }

  event AuctionStarted(uint indexed _startBlock);
  event AuctionBid(address indexed _sender, uint _amount, uint _missingFunds);
  event AuctionClaim(address indexed _recipient, uint _sentAmount);
  event AuctionFinalized(uint _finalPrice);

  function DutchAuction(
    address _clnyToken,
    address _token,
    uint256 _quantity,
    uint _startPrice) 
    public 
    {
    colonyNetwork = msg.sender;
    require(_clnyToken != 0x0 && _token != 0x0);
    clnyToken = ERC20Extended(_clnyToken);
    token = ERC20Extended(_token);
    
    require(_startPrice > 0);
    startPrice = _startPrice;
    require(_quantity > 0);
    quantity = _quantity;
    startBlock = block.number;
    AuctionStarted(startBlock);
  }

  function bid(uint256 _amount) public
  auctionNotFinalized
  endBlockNotSet
  {
    require(_amount > 0);
    uint _totalToEndAuction = totalToEndAuction();
    uint remainingToEndAuction = sub(_totalToEndAuction, receivedTotal);

    // Adjust the amount for final bid in case that takes us over the offered quantity at current price
    // Also conditionally set the endBlock
    uint amount;
    if (remainingToEndAuction > _amount) {
      amount = _amount;
    } else {
      amount = remainingToEndAuction;
      endBlock = block.number;
    }
    
    clnyToken.transferFrom(msg.sender, this, amount);
    bids[msg.sender] = add(bids[msg.sender], amount);
    receivedTotal = add(receivedTotal, amount);
    
    AuctionBid(msg.sender, amount, sub(remainingToEndAuction, amount));
  }

  // Finalize the auction and sets the final Token price
  function finalize() public
  auctionNotFinalized
  endBlockSet
  {
    // Give the network all CLNY sent to the auction in bids
    clnyToken.transfer(colonyNetwork, receivedTotal);
    finalPrice = mul(receivedTotal, MULTIPLIER) / quantity;
    finalized = true;
    AuctionFinalized(finalPrice);
  }

  function claim() public 
  auctionFinalized
  returns (bool)
  {
    uint amount = bids[msg.sender];
    uint tokens = mul(amount, MULTIPLIER) / finalPrice;

    // Due to finalPrice floor rounding, the number of assigned tokens may be higher
    // than expected. Therefore, the number of remaining unassigned auction tokens
    // may be smaller than the number of tokens needed for the last claimTokens call
    uint auctionTokenBalance = token.balanceOf(address(this));
    if (tokens > auctionTokenBalance) {
      tokens = auctionTokenBalance;
    }

    // Update the total amount of funds for which tokens have been claimed
    tokensClaimed += amount;

    // Set receiver bid to 0 before transferring the tokens
    bids[msg.sender] = 0;
    require(token.transfer(msg.sender, tokens));
    AuctionClaim(msg.sender, tokens);

    assert(token.balanceOf(msg.sender) >= tokens);
    assert(bids[msg.sender] == 0);
    return true;
  }

  function totalToEndAuction() public view returns (uint) {
    return (quantity * price()) / MULTIPLIER;
  }

  // Get the current Token price in CLNY wei
  // If the end block is set, i.e. auction is closed for bids, use the endBlock in calculation
  function price() public view returns (uint) {
    uint lastBlock = endBlock == 0 ? block.number : endBlock;
    return startPrice * MULTIPLIER / (1 + lastBlock - startBlock);
  }

  function close() public
  auctionFinalized
  allBidsClaimed
  {
    assert(clnyToken.balanceOf(this) == 0);
    assert(token.balanceOf(this) == 0);
    selfdestruct(colonyNetwork);
  }
}