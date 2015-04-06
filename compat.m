//
//  compat.m
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

#import "compat.h"

// ugly clutches to make some stuff visible to Swift
const mach_msg_type_number_t kHOST_BASIC_INFO_COUNT = HOST_BASIC_INFO_COUNT;

const xpc_object_t xpc_error_connection_interrupted = XPC_ERROR_CONNECTION_INTERRUPTED;
const xpc_object_t xpc_error_connection_invalid = XPC_ERROR_CONNECTION_INVALID;
const xpc_object_t xpc_error_termination_imminent = XPC_ERROR_TERMINATION_IMMINENT;

const xpc_type_t xpc_type_error = XPC_TYPE_ERROR;
const xpc_type_t xpc_type_connection = XPC_TYPE_CONNECTION;
