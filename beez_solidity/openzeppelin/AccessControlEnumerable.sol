// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// import "./IAccessControlEnumerable.sol";
// import "./AccessControl.sol";
// import "../utils/structs/EnumerableSet.sol";

import "./IAccessControlEnumerable.sol";
import "./AccessControl.sol";
import "./EnumerableSet.sol";

abstract contract AccessControlEnumerable is IAccessControlEnumerable, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(bytes32 => EnumerableSet.AddressSet) private _roleMembers;


    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlEnumerable).interfaceId || super.supportsInterface(interfaceId);
    }
    
    function _setupRole(bytes32 role, address account) internal virtual override {
        super._setupRole(role, account);
        _roleMembers[role].add(account);
    }

    // function getRoleMember(bytes32 role, uint256 index) external view override returns (address) {
    //     return _roleMembers[role].at(index);
    // }

    // function getRoleMemberCount(bytes32 role) private view override returns (uint256) {
    //     return _roleMembers[role].length();
    // }

    // function grantRole(bytes32 role, address account) public virtual override(AccessControl, IAccessControl) {
    //     super.grantRole(role, account);
    //     _roleMembers[role].add(account);
    // }

    // function revokeRole(bytes32 role, address account) public virtual override(AccessControl, IAccessControl) {
    //     super.revokeRole(role, account);
    //     _roleMembers[role].remove(account);
    // }

    // function renounceRole(bytes32 role, address account) public virtual override(AccessControl, IAccessControl) {
    //     super.renounceRole(role, account);
    //     _roleMembers[role].remove(account);
    // }

}