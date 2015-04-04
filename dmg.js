var finder = Application("Finder");
var disk = finder.disks["Monolingual"];
disk.open();
var window = disk.containerWindow();
window.currentView = "icon view";
window.toolbarVisible = false;
window.sidebarWidth = 135;
window.bounds = {"x":30, "y":50, "width":550+135, "height":450};
var options = window.iconViewOptions();
options.iconSize = 64;
options.arrangement = "not arranged";
options.backgroundPicture = disk.files[".dmg-resources:dmg-bg.tiff"];

disk.items["Monolingual.app"].position = {"x":246, "y":43};
disk.items["COPYING.txt"].position = {"x":0, "y":43};
disk.items["README.rtfd"].position = {"x":0, "y":225};
disk.items["LisezMoi.rtfd"].position = {"x":123, "y":225};
disk.items["Lies-mich.rtfd"].position = {"x":246, "y":225};
disk.items["Leggimi.rtfd"].position = {"x":369, "y":225};
disk.items["LEESMIJ.rtfd"].position = {"x":492, "y":225};
disk.items["Applications"].position = {"x":369, "y":43};

disk.update({registeringApplications: false});
window.bounds = {"x":31, "y":50, "width":550+135, "height":450};
window.bounds = {"x":30, "y":50, "width":550+135, "height":450};
disk.update({registeringApplications: false});

disk.close();

var dsStoreFile = disk.files[".DS_Store"];
var waitTime = 0;
ObjC.import('Foundation');
var fileManager = $.NSFileManager.defaultManager;
while (!ObjC.unwrap(fileManager.fileExistsAtPath("/Volumes/Monolingual/.DS_Store"))) {
	//give the finder some time to write the .DS_Store file
	delay(1);
	waitTime++;
}
console.log("waited " + waitTime + " seconds for .DS_Store to be created");
