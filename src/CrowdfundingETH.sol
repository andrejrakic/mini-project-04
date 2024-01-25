// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ReentrancyGuard} from "./vendor/@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CrowdfundingETH is ReentrancyGuard {
  // We don't relay on address(this).balance so no point for admin withdrawal function (there is no point in reverting the receive() and fallback() function calls because ether can still arrive by selfdestructing other contract)
  struct Fundraiser {
    uint256 goal; //
    uint256 totalCollected; //
    address creator; // ────────╮
    uint48 deadline; // ────────╯
  }

  uint256 fundraiserIdCounter;

  mapping(uint256 fundraiserId => Fundraiser fundraiser) internal fundraisers;
  mapping(uint256 fundraiserId => mapping(address donator => uint256 amount)) internal donations;

  error Crowdfunding__DeadlineCantBeInPast();
  error Crowdfunding__DeadlineForDonatingPassed();
  error Crowdfunding__UnauthorizedAccess();
  error Crowfunding__FundraiserStillInProgress();
  error Crowfunding__CantWithdrawFromUnsuccessfulFundraiser();
  error Crowfunding__CantWithdrawFromSuccessfulFundraiser();

  event FundraiserCreated(uint256 fundraiserId, uint256 goal, uint48 deadline);
  event NewDonation(uint256 fundraiserId, address donator, uint256 donatedAmount);
  event FundsRaised(uint256 fundraiserId, uint256 totalCollected);
  event DonationWithdrawn(uint256 fundraiserId, address donator, uint256 withdrawnAmount);

  function createFundraiser(uint256 _goal, uint48 _deadline) external nonReentrant returns (uint256 fundraiserId) {
    if (block.timestamp > _deadline) revert Crowdfunding__DeadlineCantBeInPast();

    unchecked {
      fundraiserId = fundraiserIdCounter++;
    }

    fundraisers[fundraiserId].creator = msg.sender;
    fundraisers[fundraiserId].goal = _goal;
    fundraisers[fundraiserId].deadline = _deadline;

    emit FundraiserCreated(fundraiserId, _goal, _deadline);
  }

  function donate(uint256 _fundraiserId) external payable nonReentrant {
    Fundraiser memory fundraiser = fundraisers[_fundraiserId];
    if (block.timestamp > fundraiser.deadline) revert Crowdfunding__DeadlineForDonatingPassed();

    fundraisers[_fundraiserId].totalCollected += msg.value;
    donations[_fundraiserId][msg.sender] += msg.value;

    emit NewDonation(_fundraiserId, msg.sender, msg.value);
  }

  function withdraw(uint256 _fundraiserId) external nonReentrant {
    Fundraiser memory fundraiser = fundraisers[_fundraiserId];
    if (msg.sender != fundraiser.creator) revert Crowdfunding__UnauthorizedAccess();
    if (fundraiser.deadline > block.timestamp) revert Crowfunding__FundraiserStillInProgress();
    if (fundraiser.goal > fundraiser.totalCollected) revert Crowfunding__CantWithdrawFromUnsuccessfulFundraiser();

    delete fundraisers[_fundraiserId];

    (bool sent, ) = fundraiser.creator.call{value: fundraiser.totalCollected}("");
    require(sent, "Failed to withdraw Ether");

    emit FundsRaised(_fundraiserId, fundraiser.totalCollected);
  }

  function withdrawFromUnsuccessfulFundraiser(uint256 _fundraiserId) external nonReentrant {
    Fundraiser memory fundraiser = fundraisers[_fundraiserId];
    if (fundraiser.deadline > block.timestamp) revert Crowfunding__FundraiserStillInProgress();
    if (fundraiser.goal < fundraiser.totalCollected) revert Crowfunding__CantWithdrawFromSuccessfulFundraiser();

    uint256 amountToWithdraw = donations[_fundraiserId][msg.sender];
    donations[_fundraiserId][msg.sender] = 0;

    (bool sent, ) = msg.sender.call{value: amountToWithdraw}("");
    require(sent, "Failed to withdraw Ether");

    emit DonationWithdrawn(_fundraiserId, msg.sender, amountToWithdraw);
  }

  function getFundraiserStatus(
    uint256 _fundraiserId
  ) external view returns (bool isFinished, bool isSuccessful, uint256 goal, uint256 collectedSoFar, uint48 deadline) {
    Fundraiser memory fundraiser = fundraisers[_fundraiserId];

    isFinished = fundraiser.deadline > block.timestamp;
    isSuccessful = fundraiser.goal > fundraiser.totalCollected;
    goal = fundraiser.goal;
    collectedSoFar = fundraiser.totalCollected;
    deadline = fundraiser.deadline;
  }
}
