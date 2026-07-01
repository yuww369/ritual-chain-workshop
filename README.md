# Secure AI Bounty Evaluation System

## Contract Summary
This Solidity implementation introduces a cryptographic Commit-Reveal scheme to eliminate front-running and plagiarism risks in AI-evaluated bounties. By decoupling the submission phase from the evaluation phase, the contract ensures that no participant can view or copy another's answer before the judging window opens. The system leverages Ritual Chain’s TEE precompiles for trustless, batch-processed AI evaluation directly on-chain.

## Operational Lifecycle
1. **Bounty Initialization**: The creator deploys a bounty with an immutable rubric, deadline, and ETH reward.
2. **Blind Submission Phase**: Participants submit only the `keccak256(answer, salt, msg.sender, bountyId)` hash. The plaintext answer remains completely hidden.
3. **Reveal Phase**: After the deadline expires, participants disclose their original answer and salt. The contract cryptographically verifies each reveal against its stored commitment. Invalid or unrevealed entries are automatically discarded.
4. **Batch AI Adjudication**: The bounty owner triggers a single `judgeAll()` call, sending all verified answers to the LLM inside Ritual’s Trusted Execution Environment. This eliminates per-answer oracle costs and prevents data leakage.
5. **Payout Execution**: The owner reviews the AI-generated assessment and manually finalizes the winner, triggering an atomic reward transfer.

## Testing Strategy
| Scenario | Expected Outcome |
| :--- | :--- |
| Duplicate commitment from same address | Reverted with "Already submitted" |
| Reveal with mismatched salt | Reverted with "Invalid reveal" |
| Reveal before deadline | Reverted with "Deadline not passed" |
| Valid reveal after deadline | Answer stored in submissions array |
| judgeAll() with zero reveals | Reverted with "No submissions to judge" |
| finalizeWinner() before judging | Reverted with "Not judged yet" |

## Architectural Design
- **On-Chain Layer**: Stores only opaque commitments during the blind phase. Revealed answers exist in transient storage solely for the duration of the `judgeAll()` transaction.
- **TEE Integration**: Uses `_executePrecompile(LLM_INFERENCE_PRECOMPILE, ...)` to invoke the LLM within Ritual’s secure enclave. No third-party oracle or off-chain API is required.
- **Gas Optimization**: Batch processing reduces N separate LLM calls into a single precompile invocation, significantly lowering gas costs for large submission sets.

## Reflection Question Response
In a decentralized bounty system, the rubric, reward amount, and participant wallet addresses must remain public to ensure transparency and verifiability. Conversely, the actual content of submissions must stay encrypted or hashed until the evaluation phase concludes; premature exposure would incentivize copying and undermine the meritocratic purpose of the bounty. The AI should be responsible for the initial, objective scoring of answers against the predefined rubric, as it can process large volumes without bias or fatigue. However, the ultimate authority to declare a winner and release funds must rest with a human operator. AI models can hallucinate, misinterpret nuanced criteria, or be adversarially manipulated; human oversight acts as a necessary failsafe to preserve fairness, accountability, and participant trust in the ecosystem.