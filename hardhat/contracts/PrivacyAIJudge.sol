// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./utils/PrecompileConsumer.sol";

contract PrivacyAIJudge is PrecompileConsumer {
    uint256 public maxSubmissions = 10;
    uint256 public maxAnswerLength = 2000;
    uint256 public nextBountyId = 1;

    struct Commitment {
        bytes32 hash;
        bool exists;
    }

    struct Submission {
        address submitter;
        string answer;
    }

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint256 deadline;
        bool judged;
        bool finalized;
        string aiReview;
        uint256 winnerIndex;
        mapping(address => Commitment) commitments;
        Submission[] submissions;
    }

    struct ConvoHistory {
        string storageType;
        string path;
        string secretName;
    }

    mapping(uint256 => Bounty) public bounties;

    event BountyCreated(uint256 bountyId, address indexed owner, string title, uint256 reward, uint256 deadline);
    event CommitmentSubmitted(uint256 bountyId, address indexed submitter, bytes32 commitment);
    event AnswerRevealed(uint256 bountyId, address indexed submitter);
    event AllAnswersJudged(uint256 bountyId, string aiReview);
    event WinnerFinalized(uint256 bountyId, uint256 winnerIndex, address indexed winner, uint256 reward);

    modifier onlyOwner(uint256 _bountyId) {
        require(msg.sender == bounties[_bountyId].owner, "Not bounty owner");
        _;
    }

    modifier bountyExists(uint256 _bountyId) {
        require(bounties[_bountyId].owner != address(0), "Bounty does not exist");
        _;
    }

    function createBounty(string memory _title, string memory _rubric, uint256 _deadline) external payable returns (uint256) {
        require(msg.value > 0, "Reward must be greater than zero");
        uint256 bountyId = nextBountyId++;
        Bounty storage bounty = bounties[bountyId];
        bounty.owner = msg.sender;
        bounty.title = _title;
        bounty.rubric = _rubric;
        bounty.deadline = _deadline;
        bounty.reward = msg.value;
        emit BountyCreated(bountyId, msg.sender, _title, msg.value, _deadline);
        return bountyId;
    }

    function submitCommitment(uint256 bountyId, bytes32 commitment) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp <= bounty.deadline, "Submission deadline passed");
        require(!bounty.commitments[msg.sender].exists, "Already submitted");
        require(bounty.submissions.length < maxSubmissions, "Max submissions reached");
        bounty.commitments[msg.sender] = Commitment(commitment, true);
        emit CommitmentSubmitted(bountyId, msg.sender, commitment);
    }

    function revealAnswer(uint256 bountyId, string calldata answer, bytes32 salt) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.commitments[msg.sender].exists, "No commitment found");
        require(!bounty.judged, "Bounty already judged");
        require(bytes(answer).length <= maxAnswerLength, "Answer too long");
        bytes32 expectedHash = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
        require(expectedHash == bounty.commitments[msg.sender].hash, "Invalid reveal");
        bounty.submissions.push(Submission(msg.sender, answer));
        emit AnswerRevealed(bountyId, msg.sender);
    }

    function judgeAll(uint256 bountyId, bytes calldata llmInput) external onlyOwner(bountyId) bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(!bounty.judged, "Already judged");
        require(bounty.submissions.length > 0, "No submissions to judge");
        bytes memory output = _executePrecompile(LLM_INFERENCE_PRECOMPILE, llmInput);
        (bool hasError, bytes memory completionData, , string memory errorMessage, ConvoHistory memory history) = abi.decode(output, (bool, bytes, bytes, string, ConvoHistory));
        require(!hasError, errorMessage);
        bounty.judged = true;
        bounty.aiReview = string(completionData);
        emit AllAnswersJudged(bountyId, bounty.aiReview);
    }

    function finalizeWinner(uint256 bountyId, uint256 winnerIndex) external onlyOwner(bountyId) bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.judged, "Not judged yet");
        require(!bounty.finalized, "Already finalized");
        require(winnerIndex < bounty.submissions.length, "Invalid winner index");
        bounty.finalized = true;
        bounty.winnerIndex = winnerIndex;
        address winner = bounty.submissions[winnerIndex].submitter;
        (bool success, ) = payable(winner).call{value: bounty.reward}("");
        require(success, "Transfer failed");
        emit WinnerFinalized(bountyId, winnerIndex, winner, bounty.reward);
    }
}