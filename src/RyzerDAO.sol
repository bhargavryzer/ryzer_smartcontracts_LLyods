// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title RyzerDAO
/// @notice Gas-optimized governance engine for the Ryzer ecosystem.
/// @dev    Uses UUPS proxies, tight packing, and custom errors.
///         Storage layout is hand-crafted to avoid collisions and keep reads cheap.
contract RyzerDAO is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /*//////////////////////////////////////////////////////////////
                    CONSTANTS / IMMUTABLES (NOT IN STORAGE)
    //////////////////////////////////////////////////////////////*/
    uint256 private constant _MIN_PROPOSAL_DELAY = 1 hours;
    uint256 private constant _MAX_PROPOSAL_DELAY = 30 days;
    uint256 private constant _VOTING_DURATION = 3 days;
    uint256 private constant _EXECUTION_DEADLINE = 7 days;

    uint256 private constant _MIN_SIGNATURES = 2;
    uint256 private constant _MAX_SIGNATURES = 10;
    uint256 private constant _MIN_QUORUM = 10e18; // 10 tokens
    uint256 private constant _MAX_DESC_LEN = 1000;

    /*//////////////////////////////////////////////////////////////
                           STORAGE LAYOUT
    //////////////////////////////////////////////////////////////*/

    // SLOT 0: 20B token + 20B project  (40B total, 24B left)
    IERC20 public ryzerXToken;
    address public project;

    // SLOT 1: 2B proposalCount + 1B requiredSignatures + 1B quorumThreshold (4B total)
    uint16 public proposalCount;
    uint8 public requiredSignatures;
    uint8 public quorumThreshold; // basis-points over 100, e.g. 66 -> 66%

    // SLOT 2..N: mapping(uint256 => Proposal) proposals
    struct Proposal {
        // slot a
        uint48 startTime;
        uint48 endTime;
        uint48 deadline;
        uint40 forVotes; // fits 1T tokens @ 18 decimals
        uint40 againstVotes; // fits 1T tokens @ 18 decimals
        uint8 signatureCount;
        bool executed;
    }
    // description stored off-chain via emit only

    mapping(uint256 => Proposal) public proposals;

    // SLOT b..c: two packed bitmaps per proposal
    mapping(uint256 => mapping(uint256 => uint256)) private _voted; // 256 voters per word
    mapping(uint256 => mapping(uint256 => uint256)) private _signed; // 256 signers per word

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event DAOInitialized(address indexed ryzerXToken, address indexed project, uint8 quorumThreshold);
    event CoreContractsSet(address indexed ryzerXToken, address indexed project);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, bytes32 descriptionHash, uint48 delay);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalSigned(uint256 indexed proposalId, address indexed signer);
    event ProposalExecuted(uint256 indexed proposalId);
    event FallbackExecution(uint256 indexed proposalId);
    event SignerAdded(address indexed signer);
    event SignerRevoked(address indexed signer);
    event GovernanceParamsSet(uint8 requiredSignatures, uint8 quorumThreshold);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress();
    error InvalidDelay();
    error InsufficientBalance();
    error ProposalNotFound();
    error VotingPeriodEnded();
    error AlreadyVoted();
    error AlreadySigned();
    error InsufficientQuorum();
    error InsufficientSignatures();
    error ProposalExpired();
    error ProposalNotExpired();
    error InvalidSignatureCount();
    error InvalidParameter();
    error CannotModifyAdmin();

    /*//////////////////////////////////////////////////////////////
                           INITIALIZER
    //////////////////////////////////////////////////////////////*/
    function initialize(address _project, address _ryzerXToken, uint8 _quorumThreshold) external initializer {
        if (_project == address(0) || _ryzerXToken == address(0)) revert InvalidAddress();
        if (_project.code.length == 0 || _ryzerXToken.code.length == 0) revert InvalidAddress();
        if (_quorumThreshold < 50 || _quorumThreshold > 100) revert InvalidParameter();

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        ryzerXToken = IERC20(_ryzerXToken);
        project = _project;
        quorumThreshold = _quorumThreshold;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        emit DAOInitialized(_ryzerXToken, _project, _quorumThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN-ONLY CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    function setCoreContracts(address _ryzerXToken, address _project) external onlyRole(ADMIN_ROLE) {
        if (_project == address(0) || _ryzerXToken == address(0)) revert InvalidAddress();
        ryzerXToken = IERC20(_ryzerXToken);
        project = _project;
        emit CoreContractsSet(_ryzerXToken, _project);
    }

    function setGovernanceParams(uint8 _requiredSignatures, uint8 _quorumThreshold) external onlyRole(ADMIN_ROLE) {
        if (_requiredSignatures < _MIN_SIGNATURES || _requiredSignatures > _MAX_SIGNATURES) {
            revert InvalidSignatureCount();
        }
        if (_quorumThreshold < 50 || _quorumThreshold > 100) revert InvalidParameter();
        requiredSignatures = _requiredSignatures;
        quorumThreshold = _quorumThreshold;
        emit GovernanceParamsSet(_requiredSignatures, _quorumThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                           PROPOSAL LIFECYCLE
    //////////////////////////////////////////////////////////////*/
    function propose(string calldata description, uint48 delay) external nonReentrant whenNotPaused {
        if (ryzerXToken.balanceOf(msg.sender) < _MIN_QUORUM) revert InsufficientBalance();
        if (delay < _MIN_PROPOSAL_DELAY || delay > _MAX_PROPOSAL_DELAY) revert InvalidDelay();
        uint256 len = bytes(description).length;
        if (len == 0 || len > _MAX_DESC_LEN) revert InvalidParameter();

        uint256 id = ++proposalCount;
        uint48 start = uint48(block.timestamp + delay);
        proposals[id] = Proposal({
            startTime: start,
            endTime: start + uint48(_VOTING_DURATION),
            deadline: start + uint48(_EXECUTION_DEADLINE),
            forVotes: 0,
            againstVotes: 0,
            signatureCount: 0,
            executed: false
        });

        emit ProposalCreated(id, msg.sender, keccak256(bytes(description)), delay);
    }

    /*//////////////////////////////////////////////////////////////
                              VOTING
    //////////////////////////////////////////////////////////////*/
    function vote(uint256 proposalId, bool support) external nonReentrant whenNotPaused {
        Proposal storage p = proposals[proposalId];
        if (p.startTime == 0) revert ProposalNotFound();
        if (block.timestamp < p.startTime || block.timestamp > p.endTime) revert VotingPeriodEnded();

        uint256 bit = uint256(uint160(msg.sender));
        uint256 word = bit >> 8; // 256 voters per word
        uint256 mask = 1 << (bit & 0xff);
        if (_voted[proposalId][word] & mask != 0) revert AlreadyVoted();
        _voted[proposalId][word] |= mask;

        uint256 weight = ryzerXToken.balanceOf(msg.sender);
        if (weight < _MIN_QUORUM) revert InsufficientBalance();

        if (support) p.forVotes += uint40(weight);
        else p.againstVotes += uint40(weight);

        emit Voted(proposalId, msg.sender, support, weight);
    }

    /*//////////////////////////////////////////////////////////////
                           SIGNING & EXECUTION
    //////////////////////////////////////////////////////////////*/
    function signProposal(uint256 proposalId) external nonReentrant onlyRole(ADMIN_ROLE) whenNotPaused {
        Proposal storage p = proposals[proposalId];
        if (p.startTime == 0) revert ProposalNotFound();
        if (block.timestamp > p.deadline) revert ProposalExpired();

        uint256 bit = uint256(uint160(msg.sender));
        uint256 word = bit >> 8;
        uint256 mask = 1 << (bit & 0xff);
        if (_signed[proposalId][word] & mask != 0) revert AlreadySigned();
        _signed[proposalId][word] |= mask;

        uint256 total = uint256(p.forVotes) + p.againstVotes;
        if (total < _MIN_QUORUM || (uint256(p.forVotes) * 100) < uint256(quorumThreshold) * total) {
            revert InsufficientQuorum();
        }

        unchecked {
            if (++p.signatureCount >= requiredSignatures && !p.executed) {
                p.executed = true;
                emit ProposalExecuted(proposalId);
            }
        }

        emit ProposalSigned(proposalId, msg.sender);
    }

    function executeFallback(uint256 proposalId) external onlyRole(ADMIN_ROLE) whenNotPaused {
        Proposal storage p = proposals[proposalId];
        if (p.startTime == 0) revert ProposalNotFound();
        if (block.timestamp <= p.deadline) revert ProposalNotExpired();
        if (p.executed) revert ProposalNotFound();

        uint256 total = uint256(p.forVotes) + p.againstVotes;
        if (total < _MIN_QUORUM || (uint256(p.forVotes) * 100) < uint256(quorumThreshold) * total) {
            revert InsufficientQuorum();
        }

        p.executed = true;
        emit FallbackExecution(proposalId);
    }

    /*//////////////////////////////////////////////////////////////
                         SIGNER MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    function addSigner(address signer) external onlyRole(ADMIN_ROLE) {
        if (signer == address(0)) revert InvalidAddress();
        if (hasRole(DEFAULT_ADMIN_ROLE, signer)) revert CannotModifyAdmin();
        _grantRole(ADMIN_ROLE, signer);
        emit SignerAdded(signer);
    }

    function revokeSigner(address signer) external onlyRole(ADMIN_ROLE) {
        if (signer == address(0) || !hasRole(ADMIN_ROLE, signer)) revert InvalidAddress();
        if (hasRole(DEFAULT_ADMIN_ROLE, signer)) revert CannotModifyAdmin();
        _revokeRole(ADMIN_ROLE, signer);
        emit SignerRevoked(signer);
    }

    /*//////////////////////////////////////////////////////////////
                         PAUSABILITY
    //////////////////////////////////////////////////////////////*/
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                         UUPS AUTHORISATION
    //////////////////////////////////////////////////////////////*/
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(ADMIN_ROLE) {
        if (newImplementation.code.length == 0) revert InvalidAddress();
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW HELPERS
    //////////////////////////////////////////////////////////////*/
    function getProposalStatus(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }
}
