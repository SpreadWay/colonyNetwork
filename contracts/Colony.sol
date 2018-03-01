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

import "./ERC20Extended.sol";
import "./IColonyNetwork.sol";
import "./IColony.sol";
import "./ColonyStorage.sol";
import "./PatriciaTree/Data.sol";
import {Bits} from "./PatriciaTree/Bits.sol";


contract Colony is ColonyStorage {
  using Bits for uint;
  using Data for Data.Tree;
  using Data for Data.Node;
  using Data for Data.Edge;
  using Data for Data.Label;

  // This function, exactly as defined, is used in build scripts. Take care when updating.
  // Version number should be upped with every change in Colony or its dependency contracts or libraries.
  function version() public pure returns (uint256) { return 1; }

  function setToken(address _token) public
  auth
  {
    token = ERC20Extended(_token);
  }

  function getToken() public view returns (address) {
    return token;
  }

  function initialiseColony(address _address) public {
    require(colonyNetworkAddress == 0x0);
    colonyNetworkAddress = _address;
    potCount = 1;

    // Initialise the task update reviewers
    IColony(this).setFunctionReviewers(0xda4db249, 0, 2); // setTaskBrief => manager, worker
    IColony(this).setFunctionReviewers(0xcae960fe, 0, 2); // setTaskDueDate => manager, worker
    IColony(this).setFunctionReviewers(0x6fb0794f, 0, 1); // setTaskEvaluatorPayout => manager, evaluator
    IColony(this).setFunctionReviewers(0x2cf62b39, 0, 2); // setTaskWorkerPayout => manager, worker

    // Initialise the root domain
    domainCount += 1;
    IColonyNetwork colonyNetwork = IColonyNetwork(colonyNetworkAddress);
    uint256 rootLocalSkill = colonyNetwork.getSkillCount();
    domains[1] = Domain({
      skillId: rootLocalSkill,
      potId: 1
    });
  }

  function mintTokens(uint _wad) public
  auth
  {
    return token.mint(_wad);
  }

  function mintTokensForColonyNetwork(uint _wad) public {
    require(msg.sender == colonyNetworkAddress); // Only the colony Network can call this function
    require(this == IColonyNetwork(colonyNetworkAddress).getColony("Common Colony")); // Function only valid on the Common Colony
    token.mint(_wad);
    token.transfer(colonyNetworkAddress, _wad);
  }

  //TODO: Secure this function
  function addGlobalSkill(uint _parentSkillId) public
  returns (uint256)
  {
    IColonyNetwork colonyNetwork = IColonyNetwork(colonyNetworkAddress);
    return colonyNetwork.addSkill(_parentSkillId, true);
  }

  function addDomain(uint256 _parentSkillId) public
  localSkill(_parentSkillId)
  {
    // Note: remove that when we start allowing more domain hierarchy levels
    // Instead check that the parent skill id belongs to this colony own domain
    // Get the local skill id of the root domain
    uint256 rootDomainSkillId = domains[1].skillId;
    require(_parentSkillId == rootDomainSkillId);

    // Setup new local skill
    IColonyNetwork colonyNetwork = IColonyNetwork(colonyNetworkAddress);
    uint256 newLocalSkill = colonyNetwork.addSkill(_parentSkillId, false);

    // Add domain to local mapping
    domainCount += 1;
    potCount += 1;
    domains[domainCount] = Domain({
      skillId: newLocalSkill,
      potId: potCount
    });
  }

  function getDomain(uint256 _id) public view returns (uint256, uint256) {
    Domain storage d = domains[_id];
    return (d.skillId, d.potId);
  }

  function getDomainCount() public view returns (uint256) {
    return domainCount;
  }

  // TODO: Not sure where to put these functions
  function verifyKey(bytes key) internal view returns (bool) {
    uint256 colonyAddress;
    uint256 skillid;
    uint256 userAddress;
    assembly {
        colonyAddress := mload(add(key,32))
        skillid := mload(add(key,52)) // Colony address was 20 bytes long, so add 20 bytes
        userAddress := mload(add(key,84)) // Skillid was 32 bytes long, so add 32 bytes
    }
    colonyAddress >>= 96;
    userAddress >>= 96;
    // Require that the user is proving their own reputation in this colony.
    require(address(colonyAddress) == address(this));
    require(address(userAddress) == msg.sender);
    return true;
  }

  function verifyProof(bytes key, bytes value, uint branchMask, bytes32[] siblings) public view returns (bool) {  // solium-disable-line security/no-assign-params
    require(verifyKey(key)==true);
    Data.Label memory k = Data.Label(keccak256(key), 256);
    Data.Edge memory e;
    e.node = keccak256(value);
    for (uint i = 0; branchMask != 0; i++) {
      uint bitSet = branchMask.lowestBitSet();
      branchMask &= ~(uint(1) << bitSet);
      (k, e.label) = k.splitAt(255 - bitSet);
      uint bit;
      (bit, e.label) = e.label.chopFirstBit();
      bytes32[2] memory edgeHashes;
      edgeHashes[bit] = e.edgeHash();
      edgeHashes[1 - bit] = siblings[siblings.length - i - 1];
      e.node = keccak256(edgeHashes);
    }
    e.label = k;
    // Get roothash from colonynetwork
    bytes32 rootHash = IColonyNetwork(colonyNetworkAddress).getReputationRootHash();
    // Check that they proved their reputation in the current root state.
    require(rootHash == e.edgeHash());
    return true;
  }
}
