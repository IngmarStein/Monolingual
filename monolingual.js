/**
 *	Monolingual
 *	http://monolingual.sourceforge.net
 *
 *	Copyright (c) Ingmar Stein, Claudio Procida
 *
 */

/**
 *	Opens "external"-class links in a new browser window
 */
function override_external_links()
{
	var links = (document.links) ? document.links : document.getElementsByTagName("a");
	for (var i = 0; i < links.length; i++) {
		if (links[i].className.indexOf("external") != -1) {
			links[i].onclick = function(event) { window.open(this.href); return false; };
		}
	}
}

if (window.addEventListener) {
	window.addEventListener("load", override_external_links, true);
} else if (window.attachEvent) {
	window.attachEvent("onload", override_external_links);
}
