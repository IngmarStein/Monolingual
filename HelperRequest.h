//
//  HelperRequest.h
//  Monolingual
//
//  Created by Ingmar Stein on 09.04.15.
//
//

@import Foundation;

@interface HelperRequest : NSObject <NSSecureCoding>

@property(nonatomic, assign) BOOL dryRun;
@property(nonatomic, assign) BOOL doStrip;
@property(nonatomic, assign) uid_t uid;
@property(nonatomic, assign) BOOL trash;
@property(nonatomic, strong) NSArray *includes;
@property(nonatomic, strong) NSArray *excludes;
@property(nonatomic, strong) NSSet *bundleBlacklist;
@property(nonatomic, strong) NSSet *directories;
@property(nonatomic, strong) NSArray *files;
@property(nonatomic, strong) NSArray *thin;

@end
