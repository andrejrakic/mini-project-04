// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ReentrancyGuard} from "./vendor/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "./vendor/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "./vendor/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Crowdfunding is ReentrancyGuard {
  using SafeERC20 for IERC20;

  struct Fundraiser {
    uint256 goal; //
    uint256 totalCollected; //
    address creator; // ────────╮
    uint48 deadline; // ────────╯
    address tokenAddress; //
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
  error Crowdfunding__UnsupportedTokenAddress(address requiredTokenAddress, address providedTokenAddress);

  event FundraiserCreated(uint256 fundraiserId, address tokenAddress, uint256 goal, uint48 deadline);
  event NewDonation(uint256 fundraiserId, address donator, address tokenAddress, uint256 donatedAmount);
  event FundsRaised(uint256 fundraiserId, uint256 totalCollected);
  event DonationWithdrawn(uint256 fundraiserId, address donator, uint256 withdrawnAmount);

  function createFundraiser(
    address _tokenAddress,
    uint256 _goal,
    uint48 _deadline
  ) external nonReentrant returns (uint256 fundraiserId) {
    if (block.timestamp > _deadline) revert Crowdfunding__DeadlineCantBeInPast();

    unchecked {
      fundraiserId = fundraiserIdCounter++;
    }

    fundraisers[fundraiserId].creator = msg.sender;
    fundraisers[fundraiserId].tokenAddress = _tokenAddress;
    fundraisers[fundraiserId].goal = _goal;
    fundraisers[fundraiserId].deadline = _deadline;

    emit FundraiserCreated(fundraiserId, _tokenAddress, _goal, _deadline);
  }

  function donate(uint256 _fundraiserId, address _tokenAddress, uint256 _amount) external nonReentrant {
    Fundraiser memory fundraiser = fundraisers[_fundraiserId];
    if (block.timestamp > fundraiser.deadline) revert Crowdfunding__DeadlineForDonatingPassed();
    if (fundraiser.tokenAddress != _tokenAddress)
      revert Crowdfunding__UnsupportedTokenAddress(fundraiser.tokenAddress, _tokenAddress);

    IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);

    fundraisers[_fundraiserId].totalCollected += _amount;

    donations[_fundraiserId][msg.sender] += _amount;

    emit NewDonation(_fundraiserId, msg.sender, _tokenAddress, _amount);
  }

  function withdraw(uint256 _fundraiserId) external nonReentrant {
    Fundraiser memory fundraiser = fundraisers[_fundraiserId];
    if (msg.sender != fundraiser.creator) revert Crowdfunding__UnauthorizedAccess();
    if (fundraiser.deadline > block.timestamp) revert Crowfunding__FundraiserStillInProgress();
    if (fundraiser.goal > fundraiser.totalCollected) revert Crowfunding__CantWithdrawFromUnsuccessfulFundraiser();

    delete fundraisers[_fundraiserId];
    IERC20(fundraiser.tokenAddress).safeTransfer(fundraiser.creator, fundraiser.totalCollected);

    emit FundsRaised(_fundraiserId, fundraiser.totalCollected);
  }

  function withdrawFromUnsuccessfulFundraiser(uint256 _fundraiserId) external nonReentrant {
    Fundraiser memory fundraiser = fundraisers[_fundraiserId];
    if (fundraiser.deadline > block.timestamp) revert Crowfunding__FundraiserStillInProgress();
    if (fundraiser.goal < fundraiser.totalCollected) revert Crowfunding__CantWithdrawFromSuccessfulFundraiser();

    uint256 amountToWithdraw = donations[_fundraiserId][msg.sender];
    donations[_fundraiserId][msg.sender] = 0;

    IERC20(fundraiser.tokenAddress).safeTransfer(msg.sender, amountToWithdraw);

    emit DonationWithdrawn(_fundraiserId, msg.sender, amountToWithdraw);
  }

  function getFundraiserStatus(
    uint256 _fundraiserId
  )
    external
    view
    returns (
      bool isFinished,
      bool isSuccessful,
      address tokenAddress,
      uint256 goal,
      uint256 collectedSoFar,
      uint48 deadline
    )
  {
    Fundraiser memory fundraiser = fundraisers[_fundraiserId];

    isFinished = fundraiser.deadline > block.timestamp;
    isSuccessful = fundraiser.goal > fundraiser.totalCollected;
    tokenAddress = fundraiser.tokenAddress;
    goal = fundraiser.goal;
    collectedSoFar = fundraiser.totalCollected;
    deadline = fundraiser.deadline;
  }
}
