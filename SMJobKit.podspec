Pod::Spec.new do |s|
  s.name         = "SMJobKit"
  s.version      = "0.0.1"
  s.summary      = "Framework that simplifies SMJobBless."
  s.homepage     = "https://github.com/nevir/SMJobKit"
  s.author       = { "Ian MacLeod" => "ian@nevir.net" }
  s.source       = { :git => "https://github.com/nevir/SMJobKit.git", :commit => "99dd8ef78c49035b8ae4e18d9141f6cf6dc59327" }
  s.platform     = :osx
  s.source_files = 'SMJobKit/**/*.{h,m}'
  s.framework    = 'ServiceManagement', 'Security'
  s.requires_arc = true
  s.prefix_header_contents = '#import <ServiceManagement/ServiceManagement.h>', '#import "SMJErrorTypes.h"', '#import "SMJError.h"'
  s.public_header_files = 'SMJobKit/*.h'
  s.license      = {
    :type => "Apache License",
    :text => <<-LICENSE
           DO WHATEVER THE FUCK YOU WANT, PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

            0. You just DO WHATEVER THE FUCK YOU WANT.
LICENSE
  }
  s.description  = <<-DESC
Using SMJobBless and friends is rather ...painful. SMJobKit does everything in its power to alleviate that and get you back to writing awesome OS X apps.

SMJobKit is more than just a framework/library to link against. It gives you:
- A Xcode target template for SMJobBless-ready launchd services, completely configured for proper code signing!
- A client abstraction that manages installing/upgrading your app's service(s).
- A service library that pulls in as little additional code as possible. Less surface area for security vulnerabilities!
DESC
end