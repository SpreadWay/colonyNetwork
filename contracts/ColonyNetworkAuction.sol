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
  event AuctionCreated(address auction, address token, uint256 quantity);

  function startTokenAuction(address _token) public {
    address commonColony = _colonies["Common Colony"];
    address clny = IColony(commonColony).getToken();
    DutchAuction auction = new DutchAuction(clny, _token);
    uint availableTokens = ERC20Extended(_token).balanceOf(this);
    ERC20Extended(_token).transfer(auction, availableTokens);
    AuctionCreated(address(auction), _token, availableTokens);
  }
}


// Dutch auction contract - distribution of a fixed number of tokens using an auction
// The contract code is inspired by the Raiden and Gnosis Dutch auction contracts
contract DutchAuction is DSMath {
  address public colonyNetwork;
  ERC20Extended public clnyToken;
  ERC20Extended public token;

  uint public constant START_PRICE = 10 ** 18;
  uint public constant TOKEN_DECIMALS = 10 ** 18;
  uint public startBlock;
  uint public endBlock;
  // Keep track of all CLNY wei received
  uint public receivedTotal;
  uint public bidCount;
  uint public claimCount;
  // Total number of auctioned tokens
  uint public quantity;
  // CLNY Wei per Token
  uint public finalPrice;
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
    require(claimCount == bidCount);
    _;
  }

  event AuctionStarted(uint indexed _startBlock);
  event AuctionBid(address indexed _sender, uint _amount, uint _missingFunds);
  event AuctionClaim(address indexed _recipient, uint _sentAmount);
  event AuctionFinalized(uint _finalPrice);

  function DutchAuction(address _clnyToken, address _token) public {
    colonyNetwork = msg.sender;
    require(_clnyToken != 0x0 && _token != 0x0);
    clnyToken = ERC20Extended(_clnyToken);
    token = ERC20Extended(_token);
    
    quantity = token.balanceOf(this);
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
    bidCount += 1;
    
    AuctionBid(msg.sender, amount, sub(remainingToEndAuction, amount));
  }

  // Finalize the auction and sets the final Token price
  function finalize() public
  auctionNotFinalized
  endBlockSet
  {
    // Give the network all CLNY sent to the auction in bids
    clnyToken.transfer(colonyNetwork, receivedTotal);
    finalPrice = add((mul(receivedTotal, TOKEN_DECIMALS) / quantity), 1);
    finalized = true;
    AuctionFinalized(finalPrice);
  }

  function claim() public 
  auctionFinalized
  returns (bool)
  {
    uint amount = bids[msg.sender];
    uint tokens = mul(amount, TOKEN_DECIMALS) / finalPrice;
    claimCount += 1;
    
    // Set receiver bid to 0 before transferring the tokens
    bids[msg.sender] = 0;
    uint beforeClaimBalance = token.balanceOf(msg.sender);
    require(token.transfer(msg.sender, tokens));
    assert(token.balanceOf(msg.sender) == add(beforeClaimBalance, tokens));
    assert(bids[msg.sender] == 0);

    AuctionClaim(msg.sender, tokens);
    return true;
  }

  function totalToEndAuction() public view returns (uint) {
    return mul(quantity, price());
  }

  // Get the current Token price in CLNY wei
  // If the end block is set, i.e. auction is closed for bids, use the endBlock in calculation
  function price() public view returns (uint) {
    uint lastBlock = endBlock == 0 ? block.number : endBlock;
    uint duration = sub(add(1, lastBlock), startBlock);
    return START_PRICE / duration;
  }

  function close() public
  auctionFinalized
  allBidsClaimed
  {
    uint auctionTokenBalance = token.balanceOf(this);
    token.transfer(colonyNetwork, auctionTokenBalance);
    assert(clnyToken.balanceOf(this) == 0);
    assert(token.balanceOf(this) == 0);
    selfdestruct(colonyNetwork);
  }
}