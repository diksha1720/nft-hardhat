//SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "base64-sol/base64.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RandomSVG is ERC721URIStorage, VRFConsumerBase, Ownable {
    bytes32 public keyhash;
    uint256 public fee;
    uint256 public tokenCounter;
    uint256 public price;

    //SVG params
    uint256 public maxNumberofPaths;
    uint256 public maxNumberofPathCommands;
    uint256 public size;
    string[] public pathCommands;
    string[] public colors;

    mapping(bytes32 => address) public requestIdToSender;
    mapping(bytes32 => uint256) public requestIdToTokenId;
    mapping(uint256 => uint256) public tokenIdToRandomNumber;

    event requestedRandomSVG(
        bytes32 indexed requestId,
        uint256 indexed tokenId
    );
    event createdUnfinishedRandomSVG(
        uint256 indexed tokenId,
        uint256 indexed randomNumber
    );
    event createdRandomSVG(uint256 indexed tokenId, string svg);

    constructor(
        address _vrfcoordinator,
        address _linktoken,
        bytes32 _keyhash,
        uint256 _fee
    )
        VRFConsumerBase(_vrfcoordinator, _linktoken)
        ERC721("RandomSVG", "rsNFT")
    {
        keyhash = _keyhash;
        fee = _fee;
        tokenCounter = 0;
        price = 100000000000000000;

        maxNumberofPaths = 10;
        maxNumberofPathCommands = 5;
        size = 500;
        pathCommands = ["M", "L"];
        colors = ["Blue", "red", "yellow", "blue", "white"];
    }

    function withdraw() public payable onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function create() public payable returns (bytes32 _requestId) {
        require(msg.value >= price, "Need to send more ETH");
        _requestId = requestRandomness(keyhash, fee);
        requestIdToSender[_requestId] = msg.sender;
        uint256 tokenId = tokenCounter;
        requestIdToTokenId[_requestId] = tokenId;
        tokenCounter = tokenCounter + 1;
        emit requestedRandomSVG(_requestId, tokenId);
    }

    function fulfillRandomness(bytes32 _requestId, uint256 _randomNumber)
        internal
        override
    {
        address nftOwner = requestIdToSender[_requestId];
        uint256 tokenId = requestIdToTokenId[_requestId];
        _safeMint(nftOwner, tokenId);
        tokenIdToRandomNumber[tokenId] = _randomNumber;
        emit createdUnfinishedRandomSVG(tokenId, _randomNumber);
    }

    function finishMint(uint256 _tokenId) public {
        require(
            bytes(tokenURI(_tokenId)).length <= 0,
            "tokenURI is already all set!!"
        );
        require(tokenCounter > _tokenId, "TokenId has not been minted yet!");
        require(
            tokenIdToRandomNumber[_tokenId] > 0,
            "Need to wait for chainlink VRF"
        );
        uint256 randomNumber = tokenIdToRandomNumber[_tokenId];
        string memory svg = generateSVG(randomNumber);
        string memory imageURI = svgToImageURI(svg);
        string memory tokenURI = formatTokenURI(imageURI);
        _setTokenURI(_tokenId, tokenURI);
        emit createdRandomSVG(_tokenId, svg);
    }

    function generateSVG(uint256 _randomness)
        public
        view
        returns (string memory finalSvg)
    {
        // We will only use the path element, with stroke and d elements
        uint256 numberOfPaths = (_randomness % maxNumberofPaths) + 1;
        finalSvg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' height='",
                uint2str(size),
                "' width='",
                uint2str(size),
                "'>"
            )
        );
        for (uint256 i = 0; i < numberOfPaths; i++) {
            // we get a new random number for each path
            string memory pathSvg = generatePath(
                uint256(keccak256(abi.encode(_randomness, i)))
            );
            finalSvg = string(abi.encodePacked(finalSvg, pathSvg));
        }
        finalSvg = string(abi.encodePacked(finalSvg, "</svg>"));
    }

    function generatePath(uint256 _randomness)
        public
        view
        returns (string memory pathSvg)
    {
        uint256 numberOfPathCommands = (_randomness % maxNumberofPathCommands) +
            1;
        pathSvg = "<path d='";
        for (uint256 i = 0; i < numberOfPathCommands; i++) {
            string memory pathCommand = generatePathCommand(
                uint256(keccak256(abi.encode(_randomness, size + i)))
            );
            pathSvg = string(abi.encodePacked(pathSvg, pathCommand));
        }
        string memory color = colors[_randomness % colors.length];
        pathSvg = string(abi.encodePacked(pathSvg, "' stroke='", color, "'/>"));
    }

    function generatePathCommand(uint256 _randomNumber)
        public
        view
        returns (string memory pathCommand)
    {
        pathCommand = pathCommands[_randomNumber % pathCommands.length];
        uint256 parameterOne = uint256(
            keccak256(abi.encode(_randomNumber, size * 2))
        ) % size;
        uint256 parameterTwo = uint256(
            keccak256(abi.encode(_randomNumber, size * 3))
        ) % size;
        pathCommand = string(
            abi.encodePacked(
                pathCommand,
                " ",
                uint2str(parameterOne),
                " ",
                uint2str(parameterTwo)
            )
        );
    }

    function svgToImageURI(string memory _svg)
        public
        pure
        returns (string memory)
    {
        string memory baseURL = "data:image/svg+xml;base64,";
        string memory svgBase64Encoded = Base64.encode(
            bytes(string(abi.encodePacked(_svg)))
        );
        string memory imageURI = string(
            abi.encodePacked(baseURL, svgBase64Encoded)
        );
        return imageURI;
    }

    function formatTokenURI(string memory _imageURI)
        public
        pure
        returns (string memory)
    {
        string memory baseURL = "data:application/json;base64,";
        string memory tokenURI = string(
            abi.encodePacked(
                baseURL,
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name": "SVG NFT", "description": "An NFT based on SVG","attributes":"","image":"',
                            _imageURI,
                            '"}'
                        )
                    )
                )
            )
        );
        return tokenURI;
    }

    function uint2str(uint256 _i)
        internal
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
