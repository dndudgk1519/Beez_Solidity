// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./openzeppelin/ERC20.sol";
import "./openzeppelin/AccessControlEnumerable.sol";
import "./BeezToken.sol";

contract WonToken is AccessControlEnumerable, ERC20{
    
    constructor() ERC20('WON', 'WON') {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }
    
    struct chargeStruct{
        uint256 lastChargeDate;      //마지막 인센티브 충전 날짜 체크
        uint128 wonOfMonth;         //이번달 충전 금액  //maxWonCharge - wonOfMonth[address] : 이번달 충전가능금액(charge.vue에 출력) //사용자소상공인 사용
        uint128 incentiveOfMonth;   //이번달 인센티브 금액  //maxIncentive - incentiveOfMonth[address] : 이번달 혜택가능금액(charge.vue에 출력) //사용자만 사용, 소상공인은 쓰지 않음
    }

    mapping (address => chargeStruct) chargeStructCheck;  //주소 넣어서 인센티브 구조체 가져오는 매핑
    mapping (address => uint128) incentive;               // DB에 저장할 인센티브차지 매핑
    uint128 incentiveRate;                                //인센티브 비율
    
    uint256 month = 1627743600;     //매달 초기화(이달 1일을 나타냄)
    uint8 decimals = 10**0;             //decimals 10**18 X / 10**0 = etherscan, remix 보기 편함 
    uint128 maxIncentive = 500000;  //한달 혜택가능금액
    uint128 maxWonCharge = 2000000; //한달 충전가능금액
    uint128 minWonCharge = 10000;   //충전은 10000원 이상
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    //충전결과 로그 
    event chargeResult(address indexed to, uint128 chargeAmount , uint128 chargeInc);
    //출금결과 로그
    event withDrawResult(address indexed to, uint128 withDrawAmount);
/******************************************************************************************************************/
/***사용자, 소상공인 MAIN화면 매달 초기화 함수(사용자 : 이달의 충전금액, 이달의 인센티브 & 소상공인 : 현금매출)****/

    //매달 초기화 함수
    function updateMonth(address _address, uint256 _date) private {
        //금액 충전시 마지막으로 인센티브 충전된 날짜가 지난달인 경우 (block.timestamp >= month && =>이건 빼야됨)
        if(chargeStructCheck[_address].lastChargeDate < month){
            chargeStructCheck[_address].wonOfMonth = 0;  //인센티브 밸런스 초기화(여기서 이번에 충전된 )
            chargeStructCheck[_address].incentiveOfMonth = 0; 
        }
        //(나중에 다시 block.timestamp으로 수정)
        chargeStructCheck[_address].lastChargeDate = _date; //최근 인센티브 충전된 날짜 현재시간으로 업데이트
    }
    
    //매달 변경될때, aws람다를 사용해 백앤드에 요청을 보낸다. 요청받은 백앤드는 현재 시간(UNIX시간)을 setMonth에 입력 
    function setMonth(uint256 _month) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        month = _month;
    }
    function getMonth() external view returns (uint256) {
        return month;
    }
    
/******************************************************************************************************************/
/*********사용자 충전 / 소상공인 환전&출금에 사용되는 생성(mint), 소멸(burn) /사용자, 소상공인 결재 함수***********/

    //충전
    function charge(address _to, uint256 _amount) internal virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        _mint(_to, _amount*decimals);
    }
    
    //인센티브 충전
    function incentiveCharge(address _to, uint128 _amount) internal virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        incentiveRate = _amount/10;
        _mint(_to, (_amount + incentiveRate)*decimals);
        chargeStructCheck[_to].incentiveOfMonth += incentiveRate;
    }
    //충전 + 인센티브 충전
    function chargeCheck(address _to, uint128  _amount) external {
        //한달 최대 충전량
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        updateMonth(_to, block.timestamp);    //require 전에 해줘야됨. 전달+지금충전하려는 금액이 2백이 넘으면 실행 불가.
        require(_amount >= minWonCharge);   // //최소충전금액 10000원을 넘어야 충전가능
        require(chargeStructCheck[_to].wonOfMonth + _amount <= maxWonCharge); //최대충전금액 2000000원을 넘지않아야함
        chargeStructCheck[_to].wonOfMonth += _amount;
        
        //이번달 충전금액(현재 충전할 금액을 더한)이 최대인센티브(50만원) 보다 작거나 같으면 인센티브 충전
        if(chargeStructCheck[_to].wonOfMonth <= maxIncentive){
            incentiveCharge(_to, _amount);
            incentive[_to] =  _amount/10;
            emit chargeResult(_to, _amount, _amount/10);
        }else{
            //이번달 충전 금액(현재 충전금액을 뺀)이 최대 인센티브보다 적다
            if(chargeStructCheck[_to].wonOfMonth - _amount < maxIncentive){
                uint128 inc = maxIncentive - (chargeStructCheck[_to].wonOfMonth - _amount);
                charge(_to, chargeStructCheck[_to].wonOfMonth - maxIncentive);
                incentiveCharge(_to, inc);
                incentive[_to] = inc/10;
                emit chargeResult(_to, _amount, inc/10);
            }
            else{
                charge(_to, _amount);
                incentive[_to] = 0;
                emit chargeResult(_to, _amount, 0);
            }
        }
    }
    
    //소상공인 환전 함수
    function exchangeCharge(address _to, uint128 _amount) external virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        _mint(_to, _amount*decimals);
    }
    
    //소상공인 출금 함수 
     function withDraw(address _to, uint128  _amount) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        _burn(_to, _amount*decimals);
        chargeStructCheck[_to].incentiveOfMonth += _amount;
        emit withDrawResult(_to, _amount);
     }
     
    //원화 토큰 결제
    function payment(address _sender, address _recipient, uint128 _amount, uint256 _date) external virtual returns (bool){
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        updateMonth(_recipient, _date); //_date는 나중에 뺄꺼임. 이번달 첫 결재할 경우, 소상공인 incentiveCheck[_recipient].wonOfMonth 0으로 만들기 위해 //
        _transfer(_sender, _recipient, _amount*decimals); //won 결제
        chargeStructCheck[_recipient].wonOfMonth += _amount;   //소상공인 (이번달)현금매출 증가
        return true;
    }
    
/******************************************************************************************************************/
/*************************사용자, 소상공인 MAIN화면에 출력되는 원화토큰 view 함수*********************************/

    //이달의 충전금액  ////인센티브 정확히 카운팅하는 함수  //결제히스토리용 함수
    function balanceWonOfMon(address _to) external view returns (uint128){
        if(chargeStructCheck[_to].lastChargeDate < month){
            return 0;
        }
        else{
            return chargeStructCheck[_to].wonOfMonth;
        }
    }
    
    //이번달 인센티브 확인
    function balanceIncOfMon(address _to) external view returns (uint128) {
        if(chargeStructCheck[_to].lastChargeDate < month){
            return 0;
        }
        else{
            return chargeStructCheck[_to].incentiveOfMonth;    //*(-10**18)
        }
    }
    
    //현재 보유 원화
    function balance(address _account) external view virtual returns(uint256) {
        return balanceOf(_account); //* (10 ** 18)
    }
/******************************************************************************************************************/
/***************************************************권한**********************************************************/
    function addMinter(address _address) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have admin role to addMinter");
        _setupRole(MINTER_ROLE, _address);
    }

}