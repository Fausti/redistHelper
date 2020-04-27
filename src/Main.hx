import neko.Lib;

typedef RuntimeFile = {
	var lib: Null<String>;
	var f: String;
	var ?executableFormat: String;
}

typedef ExtraCopiedFile = {
	var dir: String;
	var originalFileName: String;
	var finalFileName: String;
}

class Main {
	static var RUNTIME_FILES_WIN : Array<RuntimeFile> = [
		{ lib:null, f:"hl.exe", executableFormat:"$.exe" },
		{ lib:null, f:"libhl.dll" },
		{ lib:null, f:"msvcr120.dll" },
		{ lib:null, f:"fmt.hdll" },
		{ lib:null, f:"ssl.hdll" },

		{ lib:"heaps", f:"OpenAL32.dll" },
		{ lib:"heaps", f:"openal.hdll" },
		{ lib:"heaps", f:"ui.hdll" },
		{ lib:"heaps", f:"uv.hdll" },

		{ lib:"hlsdl", f:"SDL2.dll" },
		{ lib:"hlsdl", f:"sdl.hdll" },

		{ lib:"hlsteam", f:"steam.hdll" },
		{ lib:"hlsteam", f:"steam_api.dll" },

		{ lib:"hldx", f:"directx.hdll" },
		{ lib:"hldx", f:"d3dcompiler_47.dll" },
	];
	static var RUNTIME_FILES_MAC : Array<RuntimeFile> = [
		{ lib:null, f:"redistFiles/mac/hl", executableFormat:"$" },
		{ lib:null, f:"redistFiles/mac/libhl.dylib" },
		{ lib:null, f:"redistFiles/mac/libpng16.16.dylib" }, // fmt
		{ lib:null, f:"redistFiles/mac/libvorbis.0.dylib" }, // fmt
		{ lib:null, f:"redistFiles/mac/libvorbisfile.3.dylib" }, // fmt
		{ lib:null, f:"redistFiles/mac/libmbedtls.10.dylib" }, // SSL

		{ lib:"heaps", f:"redistFiles/mac/libuv.1.dylib" },
		{ lib:"heaps", f:"redistFiles/mac/libopenal.1.dylib" },

		{ lib:"hlsdl", f:"redistFiles/mac/libSDL2-2.0.0.dylib" },
	];
	static var SINGLE_PARAMETERS = [
		"-zip" => true,
		"-h" => true,
		"--help" => true,
		"-z" => true,
		"-v" => true,
		"--verbose" => true,
		"-hl32" => true,
	];

	static var NEW_LINE = "\n";

	static var redistHelperDir = "";
	static var projectDir = "";
	static var verbose = false;


	static function main() {
		haxe.Log.trace = function(m, ?pos) {
			if ( pos != null && pos.customParams == null )
				pos.customParams = ["debug"];

			Lib.println(Std.string(m));
		}

		if( Sys.args().length==0 )
			usage();

		// Misc parameters
		if( hasParameter("-h") || hasParameter("--help") )
			usage();
		verbose = hasParameter("-v") || hasParameter("--verbose");
		var zipping = hasParameter("-zip") || hasParameter("-z");
		var isolatedParams = getIsolatedParameters();

		// Set CWD to the directory haxelib was called
		redistHelperDir = cleanUpDirPath( Sys.getCwd() );
		projectDir = cleanUpDirPath( isolatedParams.pop() ); // call directory is passed as the last param in haxelibs
		if( verbose ) {
			Sys.println("RedistHelperDir="+redistHelperDir);
			Sys.println("ProjectDir="+projectDir);
		}
		try {
			Sys.setCwd(projectDir);
		}
		catch(e:Dynamic) {
			error("Script wasn't called using: haxelib run redistHelper [...]  (projectDir="+projectDir+")");
		}

		// List HXMLs and extra files
		var hxmlPaths = [];
		var extraFiles : Array<ExtraCopiedFile> = [];
		for(p in isolatedParams)
			if( p.indexOf(".hxml")>=0 )
				hxmlPaths.push(p);
			else {
				// Found an isolated filename to copy
				var renameParts = p.split("@");
				var originalFile = dn.FilePath.fromFile(renameParts[0]);
				if( renameParts.length==1 )
					extraFiles.push({ dir:originalFile.directoryWithSlash, originalFileName:originalFile.fileWithExt, finalFileName:originalFile.fileWithExt });
				else {
					var finalFile = dn.FilePath.fromFile(renameParts[1]);
					extraFiles.push({ dir:originalFile.directoryWithSlash, originalFileName:originalFile.fileWithExt, finalFileName:finalFile.fileWithExt });
				}
			}
		if( verbose )
			Sys.println("ExtraFiles: "+extraFiles.map( function(e) {
				if( e.originalFileName==e.finalFileName )
					return e.dir+e.originalFileName;
				else
					return e.dir+e.originalFileName+">"+e.finalFileName;
			} ));
		if( hxmlPaths.length==0 ) {
			usage();
			// // Search for HXML in project folder if no parameter was given
			// for( f in sys.FileSystem.readDirectory(projectDir) )
			// 	if( !sys.FileSystem.isDirectory(f) && f.indexOf(".hxml")>=0 )
			// 		hxmlPaths.push(f);

			// if( hxmlPaths.length==0 )
			// 	error("No HXML found in current folder.");
			// else
			// 	Lib.println("Discovered "+hxmlPaths.length+" potential HXML file(s): "+hxmlPaths.join(", "));
		}

		// Project name
		var projectName = getParameter("-p");
		if( projectName==null ) {
			var split = projectDir.split("/");
			projectName = split[split.length-2];
		}
		Lib.println("Project name: "+projectName);
		Sys.println("");

		// Output folder
		var baseRedistDir = getParameter("-o");
		if( baseRedistDir==null )
			baseRedistDir = "redist";
		if( baseRedistDir.indexOf("$")>=0 )
			error("The \"$\" in the \"-o\" parameter is deprecated. RedistHelper now exports each redistribuable to a separate folder by default.");

		// Prepare base folder
		initRedistDir(baseRedistDir, extraFiles);


		// Parse HXML files given as parameters
		for(hxml in hxmlPaths) {
			Sys.println("Parsing "+hxml+"...");
			var content = getFullHxml( hxml );

			// HL
			if( content.indexOf("-hl ")>=0 ) {
				// Build
				var directX = content.indexOf("hldx")>0;

				Lib.println("Building "+hxml+"...");
				Sys.command("haxe", [hxml]);

				function makeHl(hlDir:String, files:Array<RuntimeFile>, use32bits=false) {
					Lib.println("Packaging "+hlDir+"...");
					initRedistDir(hlDir, extraFiles);

					// Create folder
					createDirectory(hlDir);

					// Copy runtimes
					if( verbose )
						Lib.println("Copying HL runtime files to "+hlDir+"... ");
					for( r in files ) {
						if( r.lib==null || hxmlRequiresLib(hxml, r.lib) ) {
							var from = findFile(r.f, use32bits);
							if( verbose )
								Lib.println(" -> "+r.f + ( r.lib==null?"" : " [required by -lib "+r.lib+"] (source: "+from+")") );
							var toFile = r.executableFormat!=null ? StringTools.replace(r.executableFormat, "$", projectName) : r.f.indexOf("/")<0 ? r.f : r.f.substr(r.f.lastIndexOf("/")+1);
							var to = hlDir+"/"+toFile;
							if( r.executableFormat!=null && verbose )
								Lib.println(" -> Renamed executable to "+toFile);
							copy(from, to);
						}
					}

					// Copy HL bin file
					var out = getHxmlOutput(hxml,"-hl");
					copy(out, hlDir+"/hlboot.dat");

					copyExtraFilesIn(extraFiles, hlDir);
				}

				// Package HL
				if( directX ) {
					// DirectX 64bits
					makeHl(baseRedistDir+"/directx/"+projectName, RUNTIME_FILES_WIN);
					if( zipping )
						zipFolder( baseRedistDir+"/directx.zip", baseRedistDir+"/directx");

					// DirectX 32bits
					if( hasParameter("-hl32") ) {
						makeHl(baseRedistDir+"/directx32/"+projectName, RUNTIME_FILES_WIN, true); // directX 32 bits
						if( zipping )
							zipFolder( baseRedistDir+"/directx32.zip", baseRedistDir+"/directx32");
					}
				}
				else {
					// SDL Windows 64bits
					makeHl(baseRedistDir+"/sdl_win/"+projectName, RUNTIME_FILES_WIN);
					if( zipping )
						zipFolder( baseRedistDir+"/sdl_win.zip", baseRedistDir+"/sdl_win/");

					// SDL Windows 32bits
					if( hasParameter("-hl32") ) {
						makeHl(baseRedistDir+"/sdl_win32/"+projectName, RUNTIME_FILES_WIN, true);
						if( zipping )
							zipFolder( baseRedistDir+"/sdl_win32.zip", baseRedistDir+"/sdl_win32/");
					}

					// SDL Mac
					makeHl(baseRedistDir+"/sdl_mac/"+projectName, RUNTIME_FILES_MAC);
					if( zipping )
						zipFolder( baseRedistDir+"/sdl_mac.zip", baseRedistDir+"/sdl_mac/");
				}
				Sys.println("");
			}

			// JS
			if( content.indexOf("-js ")>=0 ) {
				// Build
				var jsDir = baseRedistDir+"/js";
				initRedistDir(jsDir, extraFiles);

				Lib.println("Building "+hxml+"...");
				Sys.command("haxe", [hxml]);

				Lib.println("Packaging "+jsDir+"...");
				var out = getHxmlOutput(hxml,"-js");
				copy(out, jsDir+"/client.js");

				// Create HTML
				Lib.println("Creating HTML...");
				var fi = sys.io.File.read(redistHelperDir+"redistFiles/webgl.html");
				var html = "";
				while( !fi.eof() )
				try { html += fi.readLine()+NEW_LINE; } catch(e:haxe.io.Eof) {}
				html = StringTools.replace(html, "%project%", projectName);
				html = StringTools.replace(html, "%js%", "client.js");
				var fo = sys.io.File.write(jsDir+"/index.html", false);
				fo.writeString(html);
				fo.close();

				copyExtraFilesIn(extraFiles, jsDir);
				if( zipping )
					zipFolder( baseRedistDir+"/js.zip", jsDir);

				Lib.println("");
			}

			// SWF
			if( content.indexOf("-swf ")>=0 ) {
				var swfDir = baseRedistDir+"/swf";
				initRedistDir(swfDir, extraFiles);

				Lib.println("Building "+hxml+"...");
				Sys.command("haxe", [hxml]);

				Lib.println("Packaging "+swfDir+"...");
				var out = getHxmlOutput(hxml,"-swf");
				copy(out, swfDir+"/"+projectName+".swf");

				copyExtraFilesIn(extraFiles, swfDir);
				if( zipping )
					zipFolder( baseRedistDir+"/swf.zip", swfDir);

				Lib.println("");
			}
		}

		Lib.println("Done.");
	}

	static function copyExtraFilesIn(extraFiles:Array<ExtraCopiedFile>, targetPath:String) {
		for(f in extraFiles) {
			if( verbose )
				Lib.println(" -> Copying file "+projectDir+f.dir+f.originalFileName+" to "+targetPath+"/"+f.finalFileName);
			copy(projectDir+f.dir+f.originalFileName, targetPath+"/"+f.finalFileName);
		}
	}

	static function zipFolder(zipPath:String, basePath:String) {
		if( zipPath.indexOf(".zip")<0 )
			zipPath+=".zip";

		Lib.println("Zipping "+basePath+"...");
		if( !verbose )
			Lib.print(" -> ");

		// List entries
		var entries : List<haxe.zip.Entry> = new List();
		var pendingDirs = [basePath];
		while( pendingDirs.length>0 ) {
			var cur = pendingDirs.shift();
			for( fName in sys.FileSystem.readDirectory(cur) ) {
				var path = cur+"/"+fName;
				if( sys.FileSystem.isDirectory(path) ) {
					pendingDirs.push(path);
					entries.add({
						fileName: path.substr(basePath.length+1) + "/",
						fileSize: 0,
						fileTime: sys.FileSystem.stat(path).ctime,
						data: haxe.io.Bytes.alloc(0),
						dataSize: 0,
						compressed: false,
						crc32: null,
					});
				}
				else {
					var bytes = sys.io.File.getBytes(path);
					entries.add({
						fileName: path.substr(basePath.length+1),
						fileSize: sys.FileSystem.stat(path).size,
						fileTime: sys.FileSystem.stat(path).ctime,
						data: bytes,
						dataSize: bytes.length,
						compressed: false,
						crc32: null,
					});
				}
			}
		}

		// Zip entries
		var out = new haxe.io.BytesOutput();
		for(e in entries)
			if( e.data.length>0 ) {
				if( verbose )
					Sys.println(" -> Compressing: "+e.fileName+" ("+e.fileSize+" bytes)");
				else
					Sys.print("*");
				e.crc32 = haxe.crypto.Crc32.make(e.data);
				haxe.zip.Tools.compress(e,9);
			}
		var w = new haxe.zip.Writer(out);
		w.write(entries);
		Lib.println(" -> Created "+zipPath+" ("+out.length+" bytes)");
		sys.io.File.saveBytes(zipPath, out.getBytes());
	}

	static function findFile(f:String, use32bits=false) {
		if( sys.FileSystem.exists(redistHelperDir+f) )
			return redistHelperDir+f;

		// Locate haxe tools
		var haxeTools = ["haxe.exe", "hl.exe", "neko.exe" ];
		var paths = [];
		for(path in Sys.getEnv("path").split(";")) {
			path = cleanUpDirPath(path);
			for(f in haxeTools)
				if( sys.FileSystem.exists(path+f) ) {
					paths.push(path);
					break;
				}
		}

		if( use32bits ) {
			// Prioritize 32bits files over 64bits
			paths.insert(0, redistHelperDir+"redistFiles/hl32/");  // HL
		}
		paths.push(redistHelperDir+"redistFiles/");

		if( paths.length<=0 )
			throw "Haxe tools not found ("+haxeTools.join(", ")+") in PATH!";

		for(path in paths)
			if( sys.FileSystem.exists(path+f) )
				return path+f;

		throw "File not found: "+f+", lookup paths="+paths.join(", ");
	}

	static function cleanUpDirPath(path:String) {
		var fp = dn.FilePath.fromDir(path);
		fp.convertToSlashes();
		return fp.directoryWithSlash;
	}

	static function initRedistDir(d:String, extraFiles:Array<ExtraCopiedFile>) {
		if( verbose )
			Lib.println("Initializing folder: "+d+"...");
		try {
			var cwd = StringTools.replace( Sys.getCwd(), "\\", "/" );
			var abs = StringTools.replace( sys.FileSystem.absolutePath(d), "\\", "/" );
			if( abs.indexOf(cwd)<0 || abs==cwd )
				error("For security reasons, target folder should be nested inside current folder.");
			// avoid deleting unexpected files
			directoryContainsOnly(
				d,
				["exe","dat","dll","hdll","js","swf","html","dylib","zip"],
				extraFiles.map( function(e) return e.finalFileName)
			);
			removeDirectory(d);
			createDirectory(d);
		}
		catch(e:Dynamic) {
			error("Couldn't initialize dir "+d+". Maybe it's in use or opened somewhere right now?");
		}
	}


	static function getFullHxml(f:String) {
		var lines = sys.io.File.read(f, false).readAll().toString().split(NEW_LINE);
		var i = 0;
		while( i<lines.length ) {
			if( lines[i].indexOf(".hxml")>=0 && lines[i].indexOf("-cmd")<0 )
				lines[i] = getFullHxml(lines[i]);
			i++;
		}

		return lines.join(NEW_LINE);
	}


	static function createDirectory(path:String) {
		try {
			sys.FileSystem.createDirectory(path);
		}
		catch(e:Dynamic) {
			error("Couldn't create directory "+path+". Maybe it's in use right now? [ERR:"+e+"]");
		}
	}

	static function removeDirectory(path:String) {
		if( !sys.FileSystem.exists(path) )
			return;

		for( e in sys.FileSystem.readDirectory(path) ) {
			if( sys.FileSystem.isDirectory(path+"/"+e) )
				removeDirectory(path+"/"+e);
			else
				sys.FileSystem.deleteFile(path+"/"+e);
		}
		sys.FileSystem.deleteDirectory(path+"/");
	}

	static function directoryContainsOnly(path:String, allowedExts:Array<String>, ignoredFiles:Array<String>) {
		if( !sys.FileSystem.exists(path) )
			return;

		for( e in sys.FileSystem.readDirectory(path) ) {
			if( sys.FileSystem.isDirectory(path+"/"+e) )
				directoryContainsOnly(path+"/"+e, allowedExts, ignoredFiles);
			else {
				var suspFile = true;
				if( e.indexOf(".")<0 )
					suspFile = false; // ignore extension-less files

				for(ext in allowedExts)
					if( e.indexOf("."+ext)>0 ) {
						suspFile = false;
						break;
					}
				for(f in ignoredFiles)
					if( f==e )
						suspFile = false;
				if( suspFile )
					error("Output folder \""+path+"\" (which will be deleted) seems to contain unexpected files like "+e);
			}
		}
	}

	static function copy(from:String, to:String) {
		try {
			sys.io.File.copy(from, to);
		}
		catch(e:Dynamic) {
			error("Can't copy "+from+" to "+to+" ("+e+")");
		}
	}

	static function getHxmlOutput(hxmlPath:String, lookFor:String) : Null<String> {
		if( hxmlPath==null )
			return null;

		if( !sys.FileSystem.exists(hxmlPath) )
			error("File not found: "+hxmlPath);

		try {
			var content = getFullHxml(hxmlPath);
			for( line in content.split(NEW_LINE) ) {
				if( line.indexOf(lookFor)>=0 )
					return StringTools.trim( line.split(lookFor)[1] );
			}
		} catch(e:Dynamic) {
			error("Could not read "+hxmlPath+" ("+e+")");
		}
		error("No "+lookFor+" output in "+hxmlPath);
		return null;
	}

	static function hxmlRequiresLib(hxmlPath:String, libId:String) : Bool {
		if( hxmlPath==null )
			return false;

		if( !sys.FileSystem.exists(hxmlPath) )
			error("File not found: "+hxmlPath);

		try {
			var fi = sys.io.File.read(hxmlPath, false);
			var content = fi.readAll().toString();
			if( content.indexOf("-lib "+libId)>=0 )
				return true;
			for(line in content.split(NEW_LINE))
				if( line.indexOf(".hxml")>=0 )
					return hxmlRequiresLib(line, libId);
		} catch(e:Dynamic) {
			error("Could not read "+hxmlPath+" ("+e+")");
		}
		return false;
	}

	static function hasParameter(id:String) {
		for( p in Sys.args() )
			if( p==id )
				return true;
		return false;
	}

	static function getParameter(id:String) : Null<String> {
		var isNext = false;
		for( p in Sys.args() )
			if( p==id )
				isNext = true;
			else if( isNext )
				return p;

		return null;
	}

	static function getIsolatedParameters() : Array<String> {
		var all = [];
		var ignoreNext = false;
		for( p in Sys.args() ) {
			if( p.charAt(0)=="-" ) {
				if( !SINGLE_PARAMETERS.exists(p) )
					ignoreNext = true;
			}
			else if( !ignoreNext )
				all.push(p);
			else
				ignoreNext = false;
		}

		return all;
	}

	// static function getIsolatedParameter(idx:Int) : Null<String> {
	// 	var i = 0;
	// 	var ignoreNext = false;
	// 	for( p in Sys.args() ) {
	// 		if( p.charAt(0)=="-" )
	// 			ignoreNext = true;
	// 		else if( !ignoreNext ) {
	// 			if( idx==i )
	// 				return p;
	// 			i++;
	// 		}
	// 		else
	// 			ignoreNext = false;
	// 	}

	// 	return null;
	// }

	static function usage() {
		Lib.println("");
		Lib.println("USAGE:");
		Lib.println("  haxelib run redistHelper <hxml1> [<hxml2>] [<hxml3>] [customFile1] [customFile2]");
		Lib.println("");
		Lib.println("EXAMPLES:");
		Lib.println("  haxelib run redistHelper myGame.hxml");
		Lib.println("  haxelib run redistHelper myGame.hxml docs/CHANGELOG.md docs/LICENSE");
		Lib.println("  haxelib run redistHelper myGame.hxml docs/README@read_me.txt");
		Lib.println("");
		Lib.println("OPTIONS:");
		Lib.println("  -o <outputDir>: change the default redistHelper output dir (default: \"redist/\")");
		Lib.println("  -p <projectName>: change the default project name (if not provided, it will use the name of the parent folder where this script is called)");
		Lib.println("  -hl32: when building Hashlink targets, this option will also package a 32bits version of the HL runtime in separate redist folders.");
		Lib.println("  -zip: create a zip file for each build");
		Lib.println("  -h: show this help");
		Lib.println("  -v: verbose mode (display more informations)");
		Lib.println("");
		Lib.println("NOTES:");
		// Lib.println("  - If no HXML is given, the script will pick all HXMLs found in current folder.");
		Lib.println("  - All specificied \"Custom files\" will be copied in each redist folders (can be useful for README, LICENSE, etc.)");
		Lib.println("  - Custom files can be renamed after copy, just add \"@\" followed by the final name after the file path. Example:");
		Lib.println("      haxelib run redistHelper myGame.hxml docs/README@read_me.txt");
		Lib.println("      The \"README\" file from docs/ will be renamed to \"read_me.txt\" in the target folder.");
		Lib.println("");
		Sys.exit(0);
	}

	static function error(msg:Dynamic) {
		Lib.println("");
		Lib.println("ERROR - "+Std.string(msg));
		Sys.exit(1);
	}
}


