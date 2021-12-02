// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BeezToken.sol";
import "./WonToken.sol";

contract Payment {
    
    WonToken wonTokenAddr;
    BeezToken bzTokenAddr;
    address owner;
// -----------------------------------------------struct-----------------------------------------------

    struct Receipt{
        uint visitTime;
        address visitor;
        address recipient;  
        uint128 cost;
        uint128 wonTokenCount;
        uint128 bzTokenCount;  
        string value1;
        string value2;
        string value3;
    }
    struct Main{
        uint256 wonBalace;  //사용가능 금액
        uint128 WonOfMon;   //이달의 충전금액
        uint128 IncOfMon;   //이달의 인센티브
        uint256 BzBalace;   //사용가능 비즈
        uint128 BzOfMon;    //이달의 BEEZ
    }
// -----------------------------------------------mapping---------------------------------------

    mapping (address=>bytes32[]) public reviewReceipts;
    mapping (bytes32 => Receipt) public receipts;
    
// -----------------------------------------------modifier-----------------------------------------------

    modifier costCheck(uint cost, uint wonTokenCount, uint bzTokenCount){
        require(cost == (wonTokenCount + bzTokenCount));
        _;
    }
    
// -----------------------------------------------event-----------------------------------------------
    //결제결과 로그 
    event paymentResult( address indexed to, address indexed recipient, uint128 wonAmount , uint128 bzAmount);
    //환전결과 로그
    event exchangeResult(address indexed to, uint128 withDrawAmount);
    //리뷰 결과 로그
    event reviewResult(address indexed to);

    constructor() {
        owner = msg.sender;
    }
    modifier onlyOwner {
        require(msg.sender == owner, "Only Owner can call this function.");
        _;
    }

/******************************************************************************************************************/
/*************************************사용자, 소상공인 Main 출력 함수*********************************************/
    //매달 변경될때, aws람다를 사용해 백앤드에 요청을 보낸다. 요청받은 백앤드는 현재 시간(UNIX시간)을 setMonth에 입력 
    function getMonth() public view returns (uint256 getMonthWon, uint256 getMonthBz) {
        getMonthWon = wonTokenAddr.getMonth();
        getMonthBz = bzTokenAddr.getMonth();
    }
    function setMonth(uint256 _month) external onlyOwner {
        wonTokenAddr.setMonth(_month);
        bzTokenAddr.setMonth(_month);
    }
    //토큰CA를 한번만 setting하기 onlyOwner
    function setTokenCA(WonToken _wonTokenAddr, BeezToken _bzTokenAddr) external onlyOwner {
        wonTokenAddr = _wonTokenAddr;
        bzTokenAddr = _bzTokenAddr;
    }
    
    //wonToken : mint(생성), beezToken : burn(소멸)   //시스템이 해야될 일
    function exchange(address _to, uint128 _amount) external onlyOwner {
        wonTokenAddr.exchangeCharge(_to, _amount);
        bzTokenAddr.exchangeBurn(_to, _amount);
        
        emit exchangeResult(_to, _amount);
    }
    
/******************************************************************************************************************/
/*************************************사용자, 소상공인 Main 출력 함수*********************************************/

// (사용자는 영수증을 검색하고(결제내역확인), 영수증에 리뷰가 작성 되어 있는지 파악.
// 	    => vue단에서 확인)
// (소상공인은 영수증을 검색하고(결제내역확인), 결제 내역 출력.
// 	    => 리뷰가 존재하면 리뷰 출력, 없으면 결제 내역만 출력)

    //receipt creation 결제(영수증 생성)
    //결제 내역 로딩용 영수증 
    function createReceipt(uint _visitTime, address _visitor, address _recipient, uint128 _cost,  uint128 _wonTokenCount, uint128 _bzTokenCount, string memory _value1, string memory _value2 , string memory _value3) internal {
    // history에저장할떄 receipt가아니라 hash값을 넣는다. 검색기준을 receipt가아니라 hash로 해서 크기를 줄일 수있음
 
        Receipt memory rc = Receipt(_visitTime, _visitor, _recipient, _cost, _wonTokenCount, _bzTokenCount, _value1, _value2, _value3);
        
        bytes32 receiptHash = keccak256(abi.encode(rc.visitTime, rc.visitor, rc.recipient, rc.cost,rc.wonTokenCount,rc.bzTokenCount,rc.value1,rc.value2,rc.value3));
       
        reviewReceipts[_recipient].push(receiptHash); //소상공인용 리뷰 찾는 매핑
        reviewReceipts[_visitor].push(receiptHash); //방문자용 리뷰 찾는 매핑
        receipts[receiptHash] = rc;
    
    }
    
    //receipt creation 결제(영수증 생성2)
    function payment(address _visitor, address _recipient, uint128 _cost, uint128 _wonAmount, uint128 _bzAmount) external costCheck(_cost, _wonAmount,_bzAmount){
        require(msg.sender == _visitor);
        require(wonTokenAddr.balance(_visitor) >= _wonAmount);
        require(bzTokenAddr.balance(_visitor) >= _bzAmount);
        
        uint visitTime =  block.timestamp;
        wonTokenAddr.payment(_visitor, _recipient, _wonAmount, visitTime);
        bzTokenAddr.payment(_visitor, _recipient, _wonAmount, _bzAmount, visitTime);    //_wonAmount가져가는 이유 : payback때문에

        string memory _value1="";
        string memory _value2="";
        string memory _value3="";
        
        createReceipt(visitTime, _visitor,_recipient, _cost,_wonAmount,_bzAmount, _value1, _value2, _value3); //영수증 생성
        emit paymentResult(_visitor, _recipient, _wonAmount , _bzAmount);
    }

    //사용자 영수증(리뷰) 조회
    function getReview(address _address, uint _rangeDate1, uint _rangeDate2) external view returns(Receipt[] memory){
        
        uint64 arrayCnt;
        uint time;
        
        for(uint i=reviewReceipts[ _address ].length; i >= 1; i--){
            bytes32 receiptHash = reviewReceipts[ _address ][i-1];
            time = receipts[ receiptHash ].visitTime;
            
            //기간일수 검색(7,30,90,180 등)
            if(_rangeDate2 == 0){
                if(time < block.timestamp - (86400 * _rangeDate1)) {
                    break;
                }
                arrayCnt++;
            }
            //기간설정 검색(2020.1.29 ~ 2020.3.20)
            else{
                if(_rangeDate1 > time){
                    break;
                }
                else if(_rangeDate1 <= time && time <= _rangeDate2 ){
                    arrayCnt++;
                }
              

            }
        }
        
        Receipt[] memory result = new Receipt[](arrayCnt);
        uint128 arrListCnt = 0;
        
        for(uint i=reviewReceipts[ _address ].length; i >= 1; i--){
            bytes32 receiptHash = reviewReceipts[ _address ][i-1];
            Receipt memory rc = receipts[ receiptHash ];
            time = rc.visitTime;
            
            //기간일수 검색(7,30,90,180 등)
            if(_rangeDate2 == 0){
                if(time < block.timestamp - (86400 * _rangeDate1)){
                    return result;
                }
                result[reviewReceipts[ _address ].length - i] = rc;
            }
            //기간설정 검색(2020.1.29 ~ 2020.3.20)
            else{
                if(_rangeDate1 > time){
                    return result;
                }
                else if(_rangeDate1 <= time && time <= _rangeDate2 ){
                    result[arrListCnt] = rc;
                    arrListCnt++;
                }
               
                
            }
        }
        return result;
    }
     
    function reviewSearch(address _visitor,uint _visitTime, uint low, uint high) internal returns(uint){
        bytes32 receiptHash;
        Receipt memory rc ;
    	uint mid;
        
    	if(low <= high) {
    		mid = (low + high) / 2;
    		receiptHash = reviewReceipts[_visitor][mid];
    		rc = receipts[ receiptHash];
    		if(_visitTime == rc.visitTime) { // 탐색 성공 
    			return mid;
    		} else if(_visitTime < rc.visitTime) {
    			// 왼쪽 부분 arr[0]부터 arr[mid-1]에서의 탐색 
    			return reviewSearch(_visitor,_visitTime,low, mid-1);  
    		} else {
    			// 오른쪽 부분 - arr[mid+1]부터 arr[high]에서의 탐색 
    			return reviewSearch(_visitor,_visitTime,  mid+1, high); 
    		}
    	}
    
    	return 1*2**256-1; // 탐색 실패 
    }
    //리뷰작성
    function writeReview(address _visitor, uint _visitTime, string memory value1, string memory value2, string memory value3) external {
         require(msg.sender == _visitor);
         require(_visitTime > block.timestamp - 7 days);
        //uint receiptTime = 1633328119;  //입력시간
        uint _receiptIndex = reviewSearch(_visitor,_visitTime, 0, reviewReceipts[ _visitor ].length );

        bytes32 receiptHash = reviewReceipts[_visitor][_receiptIndex]; // 해당 인덱스 값을 가진 byte를 찾아와서 receiptHash에 대입
        Receipt memory rc = receipts[receiptHash];//해당 byte를 가진 receipt를 rc에 대입
        if(keccak256(bytes(rc.value1)) != keccak256(bytes(""))||keccak256(bytes(rc.value2)) != keccak256(bytes(""))||keccak256(bytes(rc.value3)) != keccak256(bytes(""))){
            return;
        }
        rc.value1 = value1;  //해당 rc의 value1값을 수정
        rc.value2 = value2;  //해당 rc의 value2값을 수정
        rc.value3 = value3;  //해당 rc의 value3값을 수정

        bzTokenAddr.Payback(_visitor, rc.wonTokenCount, block.timestamp);
        receipts[receiptHash]= rc;
        
        emit reviewResult(_visitor);
    }
    
/******************************************************************************************************************/
/*************************************사용자, 소상공인 Main 출력 함수*********************************************/

    function userMainLoad(address _to) external view returns(Main memory){
        Main memory result;
        result.wonBalace = wonTokenAddr.balance(_to);          //사용가능 금액
        result.WonOfMon = wonTokenAddr.balanceWonOfMon(_to);   //이달의 충전금액
        result.IncOfMon = wonTokenAddr.balanceIncOfMon(_to);   //이달의 인센티브
        result.BzBalace= bzTokenAddr.balance(_to);             //사용가능 BEEZ
        result.BzOfMon =  bzTokenAddr.balanceBeezOfMon(_to);   //이달의 BEEZ
                
        return result;
    }
    
    //소상공인 메인 화면 출력
    function recipientMainLoad(address _recipient) external view returns(Main memory){
        // won.balanceOfWon[_recipient] + won.balanceWonOfMon[_store]; 총매출은 프론트 단에서 처리해야 할듯
        Main memory result;
        result.wonBalace = wonTokenAddr.balance(_recipient);         //출금가능현금
        result.WonOfMon = wonTokenAddr.balanceWonOfMon(_recipient);   //이번달 원매출
        result.IncOfMon = wonTokenAddr.balanceIncOfMon(_recipient);   //이달의 인센티브
        result.BzBalace = bzTokenAddr.balance(_recipient);           //출금가능 비즈
        result.BzOfMon = bzTokenAddr.balanceBeezOfMon(_recipient);    //이번달 비즈매출
        
        return result;
    }
    
/****************************************나중에 삭제*************************************************************************/
}
    