//
//  MRCOwnedReposViewModel.m
//  MVVMReactiveCocoa
//
//  Created by leichunfeng on 15/1/18.
//  Copyright (c) 2015年 leichunfeng. All rights reserved.
//

#import "MRCOwnedReposViewModel.h"
#import "MRCReposItemViewModel.h"
#import "MRCRepoDetailViewModel.h"

@interface MRCOwnedReposViewModel ()

@property (strong, nonatomic, readwrite) OCTUser *user;
@property (assign, nonatomic, readwrite) BOOL isCurrentUser;

@end

@implementation MRCOwnedReposViewModel

- (instancetype)initWithServices:(id<MRCViewModelServices>)services params:(id)params {
    self = [super initWithServices:services params:params];
    if (self) {
        self.user = [OCTUser mrc_currentUser];
    }
    return self;
}

- (void)initialize {
    [super initialize];
    
    self.shouldPullToRefresh = YES;
    self.shouldInfiniteScrolling = self.options & MRCReposViewModelOptionsPagination;

    @weakify(self)
    self.didSelectCommand = [[RACCommand alloc] initWithSignalBlock:^RACSignal *(NSIndexPath *indexPath) {
        @strongify(self)
        OCTRepository *repository = [self.dataSource[indexPath.section][indexPath.row] repository];

        MRCRepoDetailViewModel *detailViewModel = [[MRCRepoDetailViewModel alloc] initWithServices:self.services
                                                                                            params:@{ @"repository": repository }];
        [self.services pushViewModel:detailViewModel animated:YES];
        
        return [RACSignal empty];
    }];
    
    RACSignal *fetchLocalDataOnInitializeSignal = [[RACSignal
        return:nil]
        filter:^BOOL(id value) {
            @strongify(self)
            return self.options & MRCReposViewModelOptionsFetchLocalDataOnInitialize;
        }];
    
    RACSignal *starredReposDidChangeSignal = [[[NSNotificationCenter defaultCenter]
        rac_addObserverForName:MRCStarredReposDidChangeNotification object:nil]
        filter:^BOOL(id value) {
           @strongify(self)
           return self.options & MRCReposViewModelOptionsObserveStarredReposChange;
        }];
    
    RACSignal *fetchLocalDataSignal = [[fetchLocalDataOnInitializeSignal
    	merge:starredReposDidChangeSignal]
    	mapReplace:[self fetchLocalData]];
    
    RACSignal *requestRemoteDataSignal = [[self.requestRemoteDataCommand.executionSignals.flatten
    	map:^(NSArray *repositories) {
            @strongify(self)
            if (self.options & MRCReposViewModelOptionsSectionIndex) {
                [repositories sortedArrayUsingComparator:^NSComparisonResult(OCTRepository *repo1, OCTRepository *repo2) {
                    return [repo1.name caseInsensitiveCompare:repo2.name];
                }];
            }
            return repositories;
        }]
    	doNext:^(NSArray *repositories) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                if (self.options & MRCReposViewModelOptionsSaveOrUpdateRepos) {
                    [OCTRepository mrc_saveOrUpdateRepositories:repositories];
                }
                if (self.options & MRCReposViewModelOptionsSaveOrUpdateStarredStatus) {
                    [OCTRepository mrc_saveOrUpdateStarredStatusWithRepositories:repositories];
                }
            });
        }];
    
    RAC(self, repositories) = [fetchLocalDataSignal merge:requestRemoteDataSignal];
    
    RAC(self, dataSource) = [[[RACObserve(self, repositories)
		map:^(NSArray *repositories) {
            return [OCTRepository matchStarredStatusForRepositories:repositories];
        }]
    	doNext:^(NSArray *repositories) {
            @strongify(self)
            self.sectionIndexTitles = [self sectionIndexTitlesWithRepositories:repositories];
        }]
    	map:^(NSArray *repositories) {
            @strongify(self)
            return [self dataSourceWithRepositories:repositories];
        }];
}

- (BOOL)isCurrentUser {
    return [self.user.objectID isEqualToString:[OCTUser mrc_currentUserId]];
}

- (MRCReposViewModelType)type {
    return MRCReposViewModelTypeOwned;
}

- (MRCReposViewModelOptions)options {
    MRCReposViewModelOptions options = 0;
    
    options = options | MRCReposViewModelOptionsFetchLocalDataOnInitialize;
    options = options | MRCReposViewModelOptionsObserveStarredReposChange;
    options = options | MRCReposViewModelOptionsSaveOrUpdateRepos;
//    options = options | MRCReposViewModelOptionsSaveOrUpdateStarredStatus;
//    options = options | MRCReposViewModelOptionsPagination;
    options = options | MRCReposViewModelOptionsSectionIndex;
    
    return options;
}

- (NSArray *)fetchLocalData {
    return [OCTRepository mrc_fetchUserRepositories];
}

- (RACSignal *)requestRemoteDataSignalWithPage:(NSUInteger)page {
    return [[self.services
    	client]
        fetchUserRepositories].collect;
}

- (NSArray *)sectionIndexTitlesWithRepositories:(NSArray *)repositories {
    if (repositories.count == 0) return nil;
    
    if (self.options & MRCReposViewModelOptionsSectionIndex) {
        NSArray *firstLetters = [repositories.rac_sequence map:^(OCTRepository *repository) {
            return repository.name.firstLetter;
        }].array;
        
        return [[NSSet setWithArray:firstLetters].rac_sequence.array sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    }
    
    return nil;
}

- (NSArray *)dataSourceWithRepositories:(NSArray *)repositories {
    if (repositories.count == 0) return nil;
    
    NSMutableArray *repoOfRepos = [NSMutableArray new];

    if (self.options & MRCReposViewModelOptionsSectionIndex) {
        NSString *firstLetter = [repositories.firstObject name].firstLetter;
        NSMutableArray *repos = [NSMutableArray new];
        
        for (OCTRepository *repository in repositories) {
            if ([[repository.name firstLetter] isEqualToString:firstLetter]) {
                [repos addObject:[[MRCReposItemViewModel alloc] initWithRepository:repository]];
            } else {
                [repoOfRepos addObject:repos];
                
                firstLetter = repository.name.firstLetter;
                repos = [NSMutableArray new];
                
                [repos addObject:[[MRCReposItemViewModel alloc] initWithRepository:repository]];
            }
        }
        
        [repoOfRepos addObject:repos];
    } else {
        NSArray *repos = [repositories.rac_sequence map:^id(OCTRepository *repository) {
            return [[MRCReposItemViewModel alloc] initWithRepository:repository];
        }].array;
        
        [repoOfRepos addObject:repos];
    }
    
    return repoOfRepos;
}

@end
