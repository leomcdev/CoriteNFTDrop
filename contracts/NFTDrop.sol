// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "../interfaces/ICNR.sol";

/**
 * @title NFT Drop contract where users buy nfts that represents a song share for a certain artist.
 * Each song share represents a percentage of the upcoming yield of a artists new song/album will generate.
 * By holding these song shares, the investor receives APR in relation to the time schedule.
  
 * @dev Should hold no data directly to be easily upgraded
 *
 * Upgrading this contract and adding new parent can be done while there is no dynamic
 * state variables in this contract. When upgrading the contract, all new inherited contracts must be appeneded
 * to the currently inherited contracts, if any. All state variables as well as new functions 
 * must also be appended for the upgrade to be successful.
 */

contract NFTDrop is
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    bytes32 public constant ADMIN = keccak256("ADMIN");

    /**
     * @notice Called first in the initialize (NFTDrop) contract upon deployment. Functions with
     * state variables that are not stated as CONSTANTS are required to be declared with
     * the onlyInitalizing statement, to not interrupt the initialize call in this contract.
     */

    function initialize(
        address _default_admin,
        string memory _name,
        string memory _symbol,
        ICNR _CNR
    ) external initializer {
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _default_admin);

        __ERC721_init(_name, _symbol);

        CNR = _CNR;
        __Pausable_init();
    }

    // ------------ Events
    event SharesBought(address claimant, uint256[] tokenIds);
    event EarningsClaimed(
        address claimant,
        uint256 nftDropId,
        uint256[] tokenIds
    );

    ICNR private CNR;
    mapping(address => bool) public isWhitelisted;

    bool pausedTransfers;
    bool whitelistDisabled;
    mapping(uint256 => bool) public dropPaused;

    mapping(uint256 => uint256) private nextId;
    mapping(uint256 => uint256) private lastId;

    mapping(uint256 => IERC20Upgradeable) public rewardToken;
    mapping(uint256 => uint256) public totalShareEarnings;
    mapping(uint256 => uint256) public claimedEarnings;

    mapping(uint256 => uint256) private nftDropIdToNftCap;

    address serverPubKey;
    string name_;
    string symbol_;

    /**
     * @notice Creates the drop with a token cap.
     * @dev 9 zeros are added.
     */
    function createNftDrop(
        uint256 _nftDropId,
        uint256 _tokenCap,
        IERC20Upgradeable _earningsToken
    ) external onlyRole(ADMIN) {
        require(nextId[_nftDropId] == 0, "Drop already exists");
        require(
            nextId[_nftDropId] < _tokenCap,
            "Drop ID can't be higher than max token cap"
        );
        rewardToken[_nftDropId] = _earningsToken;
        nextId[_nftDropId] = _nftDropId * 1_000_000_000;
        lastId[_nftDropId] = _nftDropId * 1_000_000_000 + _tokenCap;

        nftDropIdToNftCap[_nftDropId] = _tokenCap;
    }

    /**
     * @notice Updates drop cap. If the nft sells out extremely quick and
     * the demand is high, this could be an option.
     */
    function updateNftDropCap(uint256 _nftDropId, uint256 _tokenCap)
        external
        onlyRole(ADMIN)
    {
        require(
            nextId[_nftDropId] <= _nftDropId * 1_000_000_000 + _tokenCap,
            "Drop cap can not be lower than minted amount"
        );
        lastId[_nftDropId] = _nftDropId * 1_000_000_000 + _tokenCap;

        nftDropIdToNftCap[_nftDropId] = _tokenCap;
    }

    /**
     * @notice Mints drop with respective ID as long as the max amount
     * of minted drops has not been exceeded.
     */

    function mintNftDrop(uint256 _nftDropId, uint256 _amount)
        external
        onlyRole(ADMIN)
    {
        require(
            (nextId[_nftDropId] + _amount) <= lastId[_nftDropId],
            "Amount exceeds max"
        );
        uint256 mints = nextId[_nftDropId] + _amount;

        for (uint256 i = nextId[_nftDropId]; i < mints; i++) {
            _mint(address(this), i);
        }
        nextId[_nftDropId] = mints;
    }

    /**
     * @notice Lets user claim their share in the form of nfts
     * @dev Requires server sig and the token drop to exist.
     */
    function buyShare(
        uint256[] calldata _tokenIds,
        bytes memory _prefix,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external whenNotPaused {
        bytes memory message = abi.encode(msg.sender, address(this), _tokenIds);
        require(
            ecrecover(
                keccak256(abi.encodePacked(_prefix, message)),
                _v,
                _r,
                _s
            ) == serverPubKey,
            "Invalid signature"
        );

        uint256 nftDropId = _getNftDrop(_tokenIds[0]);
        uint256 totalClaim = totalShareEarnings[nftDropId];
        _setClaimed(nftDropId, _tokenIds, totalClaim);
        _claimNftShare(address(this), msg.sender, _tokenIds);
        emit SharesBought(msg.sender, _tokenIds);
    }

    /**
     * @dev Returns the share to the contract from an investor.
     */
    function returnShare(
        address _from,
        address _to,
        uint256[] calldata _tokenIds
    ) external onlyRole(ADMIN) {
        _claimNftShare(_from, _to, _tokenIds);
    }

    /**
     * @notice Whitelists multiple users to be available for shares.
     * @dev Also deWhitelists users by setting to false.
     */
    function setWhitelisted(address[] calldata _users, bool _whitelisted)
        external
        onlyRole(ADMIN)
    {
        uint256 length = _users.length;
        for (uint256 i = 0; i < length; i++) {
            isWhitelisted[_users[i]] = _whitelisted;
        }
    }

    /**
     * @notice Used for users to claim shares.
     */
    function _claimNftShare(
        address _from,
        address _to,
        uint256[] calldata _tokenIds
    ) internal {
        uint256 length = _tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            _transfer(_from, _to, _tokenIds[i]);
        }
    }

    /**
     * @notice Set shares to claimed.
     */
    function _setClaimed(
        uint256 _nftDropId,
        uint256[] calldata _tokenIds,
        uint256 _amount
    ) internal {
        uint256 length = _tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            require(
                _getNftDrop(_tokenIds[i]) == _nftDropId,
                "Invalid token for drop"
            );
            claimedEarnings[_tokenIds[i]] = _amount;
        }
    }

    /**
     * @notice Calculates and adds the earnings to a drop.
     * @dev Add total earnings per deposit. If its a total of 10
     * deposits with a total of 10 eth, add 1 eth per time etc.
     */
    function addEarnings(
        uint256 _nftDropId,
        uint256 _totalEarningsPerTime, // total earnings
        uint256 _sharesCount, // how many nfts total for the drop
        uint256 _earningsAmountPerNFT // earnings amount per nft for corite
    ) external onlyRole(ADMIN) {
        require(
            _totalEarningsPerTime / _sharesCount == _earningsAmountPerNFT,
            "Invalid input data"
        );

        _addEarnings(
            msg.sender,
            _nftDropId,
            _totalEarningsPerTime,
            _earningsAmountPerNFT
        );
    }

    /**
     * @dev Add earnings into contract to later be added to the respecive drops.
     */
    function _addEarnings(
        address _from,
        uint256 _nftDropId,
        uint256 _totalEarnings,
        uint256 _amountPerNFT
    ) internal {
        totalShareEarnings[_nftDropId] += _amountPerNFT;
        rewardToken[_nftDropId].transferFrom(
            _from,
            address(this),
            _totalEarnings
        );
    }

    /**
     * @notice Calculates the earnings that each investor can claim.
     * @dev Adds the new value into claimed earnings and transfers the earnings to the owner.
     */
    function claimEarnings(
        address _owner,
        uint256 _nftDropId,
        uint256[] calldata _tokenIds
    ) external whenNotPaused {
        require(isWhitelisted[_owner], "Owner is not whitelisted");
        uint256 totalToGet;
        uint256 length = _tokenIds.length;
        uint256 totalEarningsPerNftDrop = totalShareEarnings[_nftDropId];
        for (uint256 i = 0; i < length; i++) {
            require(ownerOf(_tokenIds[i]) == _owner, "Invalid token owner");
            require(
                _getNftDrop(_tokenIds[i]) == _nftDropId,
                "Invalid token for drop"
            );
            totalToGet +=
                totalEarningsPerNftDrop -
                claimedEarnings[_tokenIds[i]];
            claimedEarnings[_tokenIds[i]] = totalEarningsPerNftDrop;
        }
        rewardToken[_nftDropId].transferFrom(address(this), _owner, totalToGet);
        emit EarningsClaimed(msg.sender, _nftDropId, _tokenIds);
    }

    function updateServer(address _serverPubKey) external onlyRole(ADMIN) {
        serverPubKey = _serverPubKey;
    }

    function setwhitelistDisabled(bool _disable) external onlyRole(ADMIN) {
        whitelistDisabled = _disable;
    }

    function setTransfersPaused(bool _paused) external onlyRole(ADMIN) {
        pausedTransfers = _paused;
    }

    function setDropTransfersPaused(uint256 _nftDropId, bool _paused)
        external
        onlyRole(ADMIN)
    {
        dropPaused[_nftDropId] = _paused;
    }

    function pause() external onlyRole(ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN) {
        _unpause();
    }

    /**
     * @notice Set and update name and symbol after deployment!
     */
    function setNameAndSymbol(string memory _name, string memory _symbol)
        external
        onlyRole(ADMIN)
    {
        name_ = _name;
        symbol_ = _symbol;
    }

    function name() public view override returns (string memory) {
        return name_;
    }

    function symbol() public view override returns (string memory) {
        return symbol_;
    }

    /**
     * @notice Get current drop cap
     */
    function getNftDropCap(uint256 _nftDropId) public view returns (uint256) {
        return nftDropIdToNftCap[_nftDropId];
    }

    /**
     * @notice Get total minted drops in circulation
     */
    function getTotalMinted(uint256 _nftDropId) public view returns (uint256) {
        return nextId[_nftDropId] - 1_000_000_000;
    }

    function _getNftDrop(uint256 _tokenId) internal pure returns (uint256) {
        return _tokenId / 1_000_000_000;
    }

    /**
     * @notice Overrides the _beforeTokenTransfer in the ERC721Upgradeable contract
     * @dev Checks state and that users are whitelisted.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId);
        if (!(from == address(0) || from == address(this))) {
            require(!pausedTransfers, "Transfers are currently paused");
            require(
                !dropPaused[_getNftDrop(tokenId)],
                "Drop is currently paused"
            );
            if (!whitelistDisabled) {
                require(
                    isWhitelisted[from] && isWhitelisted[to],
                    "Invalid token transfer"
                );
            }
        }
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return ICNR(CNR).getNFTURI(address(this), _tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
