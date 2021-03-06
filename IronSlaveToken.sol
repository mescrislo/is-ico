pragma solidity ^0.4.11;

contract ERC20Basic {
	uint public totalSupply;
	function balanceOf(address who) constant returns (uint);
	function transfer(address to, uint value);
	event Transfer(address indexed from, address indexed to, uint value);
}

library SafeMath {
	function mul(uint a, uint b) internal returns (uint) {
		uint c = a * b;
		assert(a == 0 || c / a == b);
		return c;
	}

	function div(uint a, uint b) internal returns (uint) {
		// assert(b > 0); // Solidity automatically throws when dividing by 0
		uint c = a / b;
		// assert(a == b * c + a % b); // There is no case in which this doesn't hold
		return c;
	}

	function sub(uint a, uint b) internal returns (uint) {
		assert(b <= a);
		return a - b;
	}

	function add(uint a, uint b) internal returns (uint) {
		uint c = a + b;
		assert(c >= a);
		return c;
	}

	function max64(uint64 a, uint64 b) internal constant returns (uint64) {
		return a >= b ? a : b;
	}

	function min64(uint64 a, uint64 b) internal constant returns (uint64) {
		return a < b ? a : b;
	}

	function max256(uint256 a, uint256 b) internal constant returns (uint256) {
		return a >= b ? a : b;
	}

	function min256(uint256 a, uint256 b) internal constant returns (uint256) {
		return a < b ? a : b;
	}

	function assert(bool assertion) internal {
		if (!assertion) {
			revert();
		}
	}
}

contract BasicToken is ERC20Basic {
	using SafeMath for uint;

	mapping(address => uint) balances;

	modifier onlyPayloadSize(uint size) {
		if(msg.data.length < size + 4) {
			revert();
		}
		_;
	}

	function transfer(address _to, uint _value) onlyPayloadSize(2 * 32) {
		balances[msg.sender] = balances[msg.sender].sub(_value);
		balances[_to] = balances[_to].add(_value);
		Transfer(msg.sender, _to, _value);
	}

	function balanceOf(address _owner) constant returns (uint balance) {
		return balances[_owner];
	}

}

contract ERC20 is ERC20Basic {
	function allowance(address owner, address spender) constant returns (uint);
	function transferFrom(address from, address to, uint value);
	function approve(address spender, uint value);
	event Approval(address indexed owner, address indexed spender, uint value);
}

contract StandardToken is BasicToken, ERC20 {

	mapping (address => mapping (address => uint)) allowed;

	function transferFrom(address _from, address _to, uint _value) onlyPayloadSize(3 * 32) {
		var _allowance = allowed[_from][msg.sender];

		balances[_to] = balances[_to].add(_value);
		balances[_from] = balances[_from].sub(_value);
		allowed[_from][msg.sender] = _allowance.sub(_value);
		Transfer(_from, _to, _value);
	}

	function approve(address _spender, uint _value) {

		if ((_value != 0) && (allowed[msg.sender][_spender] != 0)) throw;

		allowed[msg.sender][_spender] = _value;
		Approval(msg.sender, _spender, _value);
	}

	function allowance(address _owner, address _spender) constant returns (uint remaining) {
		return allowed[_owner][_spender];
	}

}

contract IronSlaveToken is StandardToken {
	string public constant NAME = "IronSlave";
	string public constant SYMBOL = "IS";
	uint public constant DECIMALS = 18;

	uint8[10] public bonusPercentages = [
		20,
		16,
		14,
		12,
		10,
		8,
		6,
		4,
		2,
		0
	];

	uint public constant NUM_OF_PHASE = 10;

	uint16 public constant BLOCKS_PER_PHASE = 150;

	address public target = 0x436510ff7cfa2C90C71CEeE85fEC1D48d4884b4A;

	uint public firstblock = 0;

	bool public unsoldTokenIssued = false;

	uint256 public constant GOAL = 50 ether;

	uint256 public constant HARD_CAP = 120 ether;

	uint public constant MAX_UNSOLD_RATIO = 675; // 67.5%

	uint256 public constant BASE_RATE = 100000;

	uint public totalEthReceived = 0;

	uint public issueIndex = 0;


	event SaleStarted();

	event SaleEnded();

	event InvalidCaller(address caller);

	event InvalidState(bytes msg);

	event Issue(uint issueIndex, address addr, uint ethAmount, uint tokenAmount);

	event SaleSucceeded();

	event SaleFailed();


	modifier onlyOwner {
		if (target == msg.sender) {
			_;
		} else {
			InvalidCaller(msg.sender);
			throw;
		}
	}

	modifier beforeStart {
		if (!saleStarted()) {
			_;
		} else {
			InvalidState("Sale has not started yet");
			throw;
		}
	}

	modifier inProgress {
		if (saleStarted() && !saleEnded()) {
			_;
		} else {
			InvalidState("Sale is not in progress");
			throw;
		}
	}

	modifier afterEnd {
		if (saleEnded()) {
			_;
		} else {
			InvalidState("Sale is not ended yet");
			throw;
		}
	}



	function start(uint _firstblock) public onlyOwner beforeStart {
		if (_firstblock <= block.number) {
			revert();
		}

		firstblock = _firstblock;
		SaleStarted();
	}

	function close() public onlyOwner afterEnd {
		if (totalEthReceived < GOAL) {
			SaleFailed();
		} else {
			issueUnsoldToken();
			SaleSucceeded();
		}
	}

	function price() public constant returns (uint tokens) {
		return computeTokenAmount(1 ether);
	}

	function () payable {
		issueToken(msg.sender);
	}

	function issueToken(address recipient) payable inProgress {
		assert(msg.value >= 0.01 ether);

		uint tokens = computeTokenAmount(msg.value);
		totalEthReceived = totalEthReceived.add(msg.value);
		totalSupply = totalSupply.add(tokens);
		balances[recipient] = balances[recipient].add(tokens);

		Issue(
				issueIndex++,
				recipient,
				msg.value,
				tokens
		     );

		if (!target.send(msg.value)) {
			revert();
		}
	}


	function computeTokenAmount(uint ethAmount) internal constant returns (uint tokens) {
		uint phase = (block.number - firstblock).div(BLOCKS_PER_PHASE);

		if (phase >= bonusPercentages.length) {
			phase = bonusPercentages.length - 1;
		}

		uint tokenBase = ethAmount.mul(BASE_RATE);
		uint tokenBonus = tokenBase.mul(bonusPercentages[phase]).div(100);

		tokens = tokenBase.add(tokenBonus);
	}

	function issueUnsoldToken() internal {
		if (unsoldTokenIssued) {
			InvalidState("Unsold token has been issued already");
		} else {
			require(totalEthReceived >= GOAL);

			uint level = totalEthReceived.sub(GOAL).div(10000 ether);
			if (level > 7) {
				level = 7;
			}

			uint unsoldRatioInThousand = MAX_UNSOLD_RATIO - 25 * level;


			uint unsoldToken = totalSupply.div(1000 - unsoldRatioInThousand).mul(unsoldRatioInThousand);

			totalSupply = totalSupply.add(unsoldToken);
			balances[target] = balances[target].add(unsoldToken);

			Issue(
					issueIndex++,
					target,
					0,
					unsoldToken
			     );

			unsoldTokenIssued = true;
		}
	}

	function saleStarted() constant returns (bool) {
		return (firstblock > 0 && block.number >= firstblock);
	}

	function saleEnded() constant returns (bool) {
		return firstblock > 0 && (saleDue() || hardCapReached());
	}

	function saleDue() constant returns (bool) {
		return block.number >= firstblock + BLOCKS_PER_PHASE * NUM_OF_PHASE;
	}

	function hardCapReached() constant returns (bool) {
		return totalEthReceived >= HARD_CAP;
	}
}
