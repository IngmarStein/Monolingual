// Lay out the mounted, writable disk image with the Finder, which is the only
// thing that can write the .DS_Store that stores the window's appearance.
//
// make-diskimage.sh passes the image's mount point as the first argument: the
// volume name on its own is ambiguous, because an image mounted while a volume
// of the same name is already attached (the Monolingual disk image itself,
// while it is open) comes up as "<name> 1".
function run(argv) {
	var mountDir = argv[0];
	var volumeName = mountDir.split("/").pop();
	var finder = Application("Finder");
	var disk = finder.disks[volumeName];
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
	disk.items["LICENSE.txt"].position = {"x":0, "y":43};
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

	// Give the Finder some time to write the .DS_Store file. Without it the
	// image opens with no layout at all and nothing says so, so this waits —
	// but not forever: a Finder that is not going to write it never will.
	ObjC.import('Foundation');
	var fileManager = $.NSFileManager.defaultManager;
	var dsStore = mountDir + "/.DS_Store";
	var waitTime = 0;
	while (!ObjC.unwrap(fileManager.fileExistsAtPath(dsStore))) {
		if (waitTime >= 60) {
			throw new Error("The Finder did not write " + dsStore);
		}
		delay(1);
		waitTime++;
	}
	console.log("waited " + waitTime + " seconds for .DS_Store to be created");
}
