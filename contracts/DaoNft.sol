// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721A.sol";
import "./DaoCredit.sol";

contract DaoNft is ERC721A, Owned {
    using Strings for uint256;

    struct Member {
        bool approved;
        uint status;
        uint last_spawn_index;
        uint256 memberTokenId;
        string name;
    }

    struct Applicant{
        bool approved;
        bool pending;
        uint spawn_support_num;
        string name;
        address applicant_owner;
    }

    struct NftParam {
        uint spawn_threshold;
        uint spawn_cost;
    }

    DaoCredit public memberBalance;

    Applicant public curApplicantDetail;
    NftParam public nftSetting;


    uint public memberAmount;    
    uint256 internal indexSpawn;

    uint256 public maxSupply = 50000; // Set this to your max # of NFTs for the collection
    uint256 public maxMintAmount = 1; // Set this to your max # of NFTs for any wallet

    string public myBaseURI = "ipfs://QmSYzXbuMPQCoGNwSWY536mxG5wcQVTgMDXinYkS5Cny7b";
    string public baseExtension = ".json"; 

    bool public genesising = false;
    bool public paused = false;


    uint private mintCode;
    uint private spawnCode;

    address[] private spawnAgree;
    address[] private spawnOppose;

    mapping(address => uint256) private addressMintedBalance;
    mapping(address => Member) private addressMember;

    event medalClaimed(address owner);
    event ApproveCode(address member, uint seccode);
    event ApplyNftCode(address member, uint seccode);
    event SpawnAgree(address member, uint agreenum);

    constructor(address addrBalance) ERC721A("DaoNft", "ABIM") {
        owner = msg.sender;

        memberBalance = DaoCredit(addrBalance);   

        nftSetting.spawn_threshold = 5;  
        nftSetting.spawn_cost = 100; 

    }

    function _baseURI() internal view virtual override returns (string memory) {
        return myBaseURI;
    }
    
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI = _baseURI();
        return bytes(baseURI).length != 0 ? string(abi.encodePacked(baseURI, "/", tokenId.toString(), baseExtension)) 
        : "ipfs://QmSYzXbuMPQCoGNwSWY536mxG5wcQVTgMDXinYkS5Cny7b/metadata.json";
    }

    function getNextTokenURI() public view returns (string memory){

        uint256 supply = totalSupply();
        require(supply + 1 <= maxSupply, "max NFT limit exceeded");
            
        uint256 newTokenId = supply;

        string memory currentBaseURI = myBaseURI; 
        return bytes(currentBaseURI).length > 0 
            ? string(abi.encodePacked(currentBaseURI, "/", newTokenId.toString(), baseExtension)) 
            : "none"; 
    }

    function resetMember(address _to) public onlyOwner{

        addressMember[_to].approved = false;

    }

    function approveMember(address _to) public onlyOwner returns (uint){
        require(!paused, "the contract is paused");      
        require(!genesising, "someone is genesising");    
        require(addressMember[_to].approved==false, "member need to be inactived");

        uint256 supply = totalSupply();
        require(supply + 1 <= maxSupply, "max NFT limit exceeded");

        addressMember[_to].approved = true;
        addressMember[_to].memberTokenId = 0;
        addressMember[_to].name = "noname";

        genesising = true;

        mintCode = memberBalance.RegisterMintSync(_to);
        
        emit ApproveCode(_to, mintCode);

        return  mintCode;
    }

    function mintOneNew(address _to, string memory memberName) public returns(uint256) {
        require(!paused, "the contract is paused"); 
        require(addressMember[_to].approved==true, "member need to be actived");
        require(addressMember[_to].memberTokenId==0, "member has already be minted");

        uint256 supply = totalSupply();
        require(supply + 1 <= maxSupply, "max NFT limit exceeded");
            
        uint256 newTokenId = supply;

        addressMintedBalance[_to]++;
        _safeMint(_to, 1);

        addressMember[_to].memberTokenId = newTokenId;
        addressMember[_to].name = memberName;   

        genesising = false;

        ///Sync to the Credit
        memberBalance.syncMintMember(mintCode, _to);     

        memberAmount++;

        return newTokenId;
    }

    function getMemberBalance() public view returns (address addrBalance ) { 
  
        return address(memberBalance);
    }

    function applyNft(string memory _name) public returns (uint ){
        require(!paused, "the contract is paused"); 
        require(addressMember[msg.sender].approved==false, "member need to be inactived");
        require(curApplicantDetail.pending==false, "someone is applying the member, pending");

        curApplicantDetail.applicant_owner = msg.sender;
        curApplicantDetail.name = _name;
        curApplicantDetail.approved = false;
        curApplicantDetail.pending = true;

        spawnCode = memberBalance.RegisterSpawnSync(msg.sender);

        delete spawnAgree;

        indexSpawn++;
        
        memberBalance.burnSpawnSync(curApplicantDetail.applicant_owner, spawnCode, msg.sender, nftSetting.spawn_cost);

        emit ApplyNftCode(msg.sender, spawnCode);

        return spawnCode;

    }

    function spawn() public returns (uint ){
        require(curApplicantDetail.pending==true && curApplicantDetail.approved==false, "no applying NFT request");
        require(addressMember[msg.sender].approved==true, "sender need to be actived");
        require(addressMember[msg.sender].last_spawn_index < indexSpawn, "you already spawned this NFT");

        spawnAgree.push(msg.sender);
 
        memberBalance.burnSpawnSync(curApplicantDetail.applicant_owner, spawnCode, msg.sender, nftSetting.spawn_cost);

        addressMember[msg.sender].last_spawn_index = indexSpawn;

        if(spawnAgree.length >= nftSetting.spawn_threshold){
            delete spawnAgree;
            curApplicantDetail.approved = true;
            curApplicantDetail.pending = false;

            uint256 supply = totalSupply();
            require(supply + 1 <= maxSupply, "max NFT limit exceeded");

            memberBalance.syncSpawnMember(spawnCode, curApplicantDetail.applicant_owner);
            spawnCode = 0;

            addressMintedBalance[curApplicantDetail.applicant_owner]++;
            _safeMint(curApplicantDetail.applicant_owner, maxMintAmount);
            addressMember[curApplicantDetail.applicant_owner].approved = true;
            addressMember[curApplicantDetail.applicant_owner].name = curApplicantDetail.name;  
                    
            memberAmount++;
        }

        emit SpawnAgree(msg.sender, spawnAgree.length);

        return  spawnAgree.length;
    }

    function spawnCallback() public returns (uint ){
        require(curApplicantDetail.pending==true && curApplicantDetail.approved==false, "no applying NFT request");
        require(addressMember[msg.sender].approved==true, "sender need to be actived");
        require(addressMember[msg.sender].last_spawn_index < indexSpawn, "you already spawned this NFT");

        if(spawnAgree.length > 0){
            memberBalance.burnSpawnSync(curApplicantDetail.applicant_owner, spawnCode, msg.sender, nftSetting.spawn_cost);
            delete spawnAgree[spawnAgree.length-1];
            spawnAgree.pop();
        }

        if(spawnAgree.length == 0){
            delete spawnAgree;
            curApplicantDetail.approved = false;
            curApplicantDetail.pending = false;
        }

        addressMember[msg.sender].last_spawn_index = indexSpawn;

        return  spawnAgree.length;
    }

    function getCurApplicantName() public view returns (string memory _name ) { 
        
        return curApplicantDetail.name;
    }

    function getSpawnAgree() public view returns (uint ) { 
        
        return spawnAgree.length;
    }

    function getMemberAmount() public view returns (uint ) { 
        
        return memberAmount;
    }

    function getSpawnCost() public view returns (uint ) { 
        uint cost = nftSetting.spawn_cost;
        return cost;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        myBaseURI = _newBaseURI;
    }

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    function setmaxMintAmount(uint256 _newmaxMintAmount) public onlyOwner {
        maxMintAmount = _newmaxMintAmount;
    }

    // nft is not transferable
    function _beforeTokenTransfers(address from, address to, uint256 tokenId, uint256 quantity)
        internal
        virtual
        override(ERC721A)
    {
        require(from == address(0) || to == address(0), "nft is not transferrable");
        super._beforeTokenTransfers(from, to, tokenId, quantity);
    }

    function isMember(address _to) public view returns (bool ){
        if(addressMember[_to].approved){
            return true;
        }else{
            return false;
        }
    }

    function getMemberName(address _to) public view returns (string memory ) { 
  
        return addressMember[_to].name ;
    } 

    function setMemberName(string memory _newName) public{ 
  
       addressMember[msg.sender].name =_newName;
    } 

    function upgradeCostPropose(uint new_threshold) public onlyOwner{
        nftSetting.spawn_threshold = new_threshold;
    }     

    function upgradeCostVote(uint new_cost) public onlyOwner{
        nftSetting.spawn_cost = new_cost;
    }      
}
