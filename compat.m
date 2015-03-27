//
//  compat.m
//  Monolingual
//
//  Created by Ingmar Stein on 14.07.14.
//
//

#import "compat.h"
@import Darwin;
@import MachO;
@import Foundation;

// ugly clutches to make some stuff visible to Swift
const int kCPU_TYPE_X86	 	   = CPU_TYPE_X86;
const int kCPU_TYPE_X86_64	   = CPU_TYPE_X86_64;
const int kCPU_TYPE_ARM		   = CPU_TYPE_ARM;
const int kCPU_TYPE_ARM64      = CPU_TYPE_ARM64;
const int kCPU_TYPE_POWERPC    = CPU_TYPE_POWERPC;
const int kCPU_TYPE_POWERPC64  = CPU_TYPE_POWERPC64;
const int kCPU_SUBTYPE_ARM_ALL = CPU_SUBTYPE_ARM_ALL;
const int kCPU_SUBTYPE_POWERPC_ALL = CPU_SUBTYPE_POWERPC_ALL;
const int kCPU_SUBTYPE_POWERPC_750 = CPU_SUBTYPE_POWERPC_750;
const int kCPU_SUBTYPE_POWERPC_7400 = CPU_SUBTYPE_POWERPC_7400;
const int kCPU_SUBTYPE_POWERPC_7450 = CPU_SUBTYPE_POWERPC_7450;
const int kCPU_SUBTYPE_POWERPC_970 = CPU_SUBTYPE_POWERPC_970;
const int kCPU_SUBTYPE_X86_ALL = CPU_SUBTYPE_X86_ALL;
const int kCPU_SUBTYPE_X86_64_ALL = CPU_SUBTYPE_X86_64_ALL;
const int kCPU_SUBTYPE_X86_64_H = CPU_SUBTYPE_X86_64_H;

const mach_msg_type_number_t kHOST_BASIC_INFO_COUNT = HOST_BASIC_INFO_COUNT;
const NSUInteger kXPC_CONNECTION_MACH_SERVICE_PRIVILEGED = XPC_CONNECTION_MACH_SERVICE_PRIVILEGED;
const size_t kXPC_ARRAY_APPEND = XPC_ARRAY_APPEND;

const xpc_type_t xpc_type_bool = XPC_TYPE_BOOL;
const xpc_type_t xpc_type_int64 = XPC_TYPE_INT64;
const xpc_type_t xpc_type_uint64 = XPC_TYPE_UINT64;
const xpc_type_t xpc_type_string = XPC_TYPE_STRING;
const xpc_type_t xpc_type_double = XPC_TYPE_DOUBLE;
const xpc_type_t xpc_type_data = XPC_TYPE_DATA;
const xpc_type_t xpc_type_array = XPC_TYPE_ARRAY;
const xpc_type_t xpc_type_dictionary = XPC_TYPE_DICTIONARY;
const xpc_type_t xpc_type_error = XPC_TYPE_ERROR;
const xpc_type_t xpc_type_connection = XPC_TYPE_CONNECTION;

const xpc_object_t xpc_error_connection_interrupted = XPC_ERROR_CONNECTION_INTERRUPTED;
const xpc_object_t xpc_error_connection_invalid = XPC_ERROR_CONNECTION_INVALID;
const xpc_object_t xpc_error_termination_imminent = XPC_ERROR_TERMINATION_IMMINENT;
