//
//  compat.h
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

@import Darwin.Mach.machine;
@import MachO.arch;
@import Foundation;

// ugly clutches to make some stuff visible to Swift
extern const mach_msg_type_number_t kHOST_BASIC_INFO_COUNT;

extern const xpc_object_t xpc_error_connection_interrupted;
extern const xpc_object_t xpc_error_connection_invalid;
extern const xpc_object_t xpc_error_termination_imminent;

extern const xpc_type_t xpc_type_error;
extern const xpc_type_t xpc_type_connection;
