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
extern const int kCPU_TYPE_X86;
extern const int kCPU_TYPE_X86_64;
extern const int kCPU_TYPE_ARM;
extern const int kCPU_TYPE_ARM64;
extern const int kCPU_TYPE_POWERPC;
extern const int kCPU_TYPE_POWERPC64;
extern const int kCPU_SUBTYPE_ARM_ALL;
extern const int kCPU_SUBTYPE_POWERPC_ALL;
extern const int kCPU_SUBTYPE_POWERPC_750;
extern const int kCPU_SUBTYPE_POWERPC_7400;
extern const int kCPU_SUBTYPE_POWERPC_7450;
extern const int kCPU_SUBTYPE_POWERPC_970;
extern const int kCPU_SUBTYPE_X86_ALL;
extern const int kCPU_SUBTYPE_X86_64_ALL;
extern const int kCPU_SUBTYPE_X86_64_H;

extern const mach_msg_type_number_t kHOST_BASIC_INFO_COUNT;
extern const NSUInteger kXPC_CONNECTION_MACH_SERVICE_PRIVILEGED;

extern const xpc_object_t xpc_error_connection_interrupted;
extern const xpc_object_t xpc_error_connection_invalid;
extern const xpc_object_t xpc_error_termination_imminent;

extern const xpc_type_t xpc_type_error;
extern const xpc_type_t xpc_type_connection;
