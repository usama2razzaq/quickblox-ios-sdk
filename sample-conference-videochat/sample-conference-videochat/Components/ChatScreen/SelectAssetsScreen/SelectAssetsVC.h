//
//  SelectAssetsVC.h
//  sample-conference-videochat
//
//  Created by Injoit on 2/6/20.
//  Copyright © 2020 Quickblox. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^SelectedImage)(UIImage * _Nullable image);

@interface SelectAssetsVC : UIViewController
@property (nonatomic, strong) SelectedImage selectedImage;
@end

NS_ASSUME_NONNULL_END
