/*
Copyright 2011 Pedro Casaubon

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
 */
package es.xperiments.media
{
	import flash.utils.ByteArray;
	import flash.display.Stage;
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.filesystem.File;
	import flash.filesystem.FileMode;
	import flash.filesystem.FileStream;
	import flash.system.Capabilities;

	/**
	 * @author xperiments
	 */
	public class StageWebViewDisk
	{
		public static const isIPHONE : Boolean = Capabilities.os.indexOf( 'iPhone' ) != -1 ? true : false;
		public static const isANDROID : Boolean = Capabilities.version.indexOf( 'AND' ) != -1 ? true : false;
		public static const isMOBILE : Boolean = ( isIPHONE || isANDROID );
		public static const isLINUX : Boolean = Capabilities.version.indexOf( 'LNX' ) != -1 ? true : false;
		public static const isMAC : Boolean = Capabilities.version.indexOf( 'MAC' ) != -1 ? true : false;
		public static const isWINDOWS : Boolean = Capabilities.version.indexOf( 'WIN' ) != -1 ? true : false;
		public static const isDESKTOP : Boolean = ( (isLINUX && !isANDROID ) || isWINDOWS || isMAC || Capabilities.isDebugger );

		public static const SENDING_PROTOCOL:String = StageWebViewDisk.isANDROID ? "tuoba:":"about:";

		public static const PROTOCOL_APP_LINK:String = "applink:/";
		public static const PROTOCOL_DOC_LINK:String = "doclink:/";

		public static var JSCODE : String;



		private static var _applicationCacheDirectory : String;
		private static var _applicationRootPath : String;
		private static var _debugMode : Boolean = false;
		private static var _appCacheFile : File ;
		private static var _cached_extensions : Array = [ "html", "htm", "css", "js" ];
		private static var _document_root : String = "www";
		private static var _document_source : String = _document_root + "Source";
		private static var _firstRun : Boolean = true;
		private static var _tmpFile : File = new File();
		private static var _fileStream : FileStream = new FileStream();
		private static var _copyFromFile : File = new File();
		private static var _copyToFile : File = new File();
		private static var _tempFileCounter : uint = 0;
		private static var _disp : EventDispatcher;
		private static var _appFileIncludeRegexp:RegExp;
		private static var _stage : Stage;
		private static var _applicationSourcesDirectory : String;
		private static const _headRegexp:RegExp = new RegExp( '<head>', 'g' );
		
		[Embed(source='StageWebViewBridge.js', mimeType="application/octet-stream")]
		private static const EMBEDJS:Class; // Embed the javascript file used in injection or remote

		/**
		 * Main init function
		 * 
		 * @param stage instance
		 * 
		 * @example
		 *	<br>
		 *	// Initialize your debug mode BEFORE!!!<br> 
		 *	StageWebViewDisk.debugMode = true;<br><br> 
		 *	// Initialize your aditionl extensions to preparse BEFORE!!!<br> 
		 *	StageWebViewDisk.setSourceFileExtensions([ "html", "htm", "css", "js", "xml" ]);<br><br> 
		 *	// Call init function<br>
		 *	StageWebViewDisk.initialize( stage )<br>
		 * 
		 */
		public static function initialize( stage:Stage ) : void
		{
			initJSCODE();
			if( stage == null ) 
			{
				throw new Error("StageWebViewDisk.initialize( stage ) :: You mus provide a valid stage instance");
			}
			_stage = stage;
			setExtensionsToProcess( _cached_extensions );
			switch( true )
			{
				// ANDROID
				case isANDROID:
					_appCacheFile = File.applicationStorageDirectory;
					_applicationCacheDirectory = new File( _appCacheFile.nativePath ).url;
					_applicationRootPath = _applicationCacheDirectory + '/' + getWorkingDir();
					_applicationSourcesDirectory =_applicationRootPath;
					
					break;
				// IOS
				case isIPHONE :
					_appCacheFile = File.applicationStorageDirectory;
					_applicationCacheDirectory = new File( _appCacheFile.nativePath ).url;
					_applicationRootPath = _applicationCacheDirectory + '/' + getWorkingDir(); 
					_applicationSourcesDirectory = 	new File( new File( "app:/"+_document_root ).nativePath ).url;	
								
					break;
				// DESKTOP OSX
				case isDESKTOP:
					_appCacheFile = new File( new File( "app:/" ).nativePath );
					_applicationCacheDirectory = _appCacheFile.url;
					_applicationRootPath = _applicationCacheDirectory + '/' + getWorkingDir(); 
					_applicationSourcesDirectory = _applicationRootPath;
					break;
			}
			


			// Determine if is ther first time that the application runs
			_firstRun = new File( _applicationCacheDirectory ).resolvePath( 'swvb.init' ).exists ? false : true;

			// If first run or in DebugMode run the "diskCaching"
			if ( _firstRun || _debugMode )
			{
				processCache();
			}
			else
			{
				dispatchEvent( new StageWebviewDiskEvent( StageWebviewDiskEvent.END_DISK_PARSING ) );
			}

			// delete our temp directory at start
			deleteTempFolder();
		}

		private static function initJSCODE() : void
		{
			var file:ByteArray = new EMBEDJS();
			var str:String = file.readUTFBytes( file.length );
			
			JSCODE = str.toString()
			.replace( new RegExp( "\\n", "g" ), "" )
			.replace( new RegExp( "\\t", "g" ), "" );			
		}

		/**
		 * Enables / Disables DEBUG MODE
		 */
		public static function setDebugMode( mode : Boolean = true ) : void
		{
			_debugMode = mode;
		}

		/**
		 * Sets the file extensions that must be preparsed into cache 
		 * @param extensions Array of extensions ex.:["html","htm","css","js"]
		 * 
		 */
		public static function setExtensionsToProcess( extensions : Array ) : void
		{
			_cached_extensions = extensions;
			_appFileIncludeRegexp = new RegExp("\(\?P<protocol>appfile:\/\)\(\?P<file>\[\\w\-\\\.\\\/%\]\+\(\?P<extension>"+extensions.join('\|')+"\)\)","gixsm");
		}

		/**
		 * Creates and parses a temporally file with the provided contents.
		 * @param contents Contents of the file.
		 * @param extension Extension of the file ( default = "html" ).
		 */
		internal static function createTempFile( contents : String, extension : String = "html" ) : File
		{
			contents = parseAppFile( contents );
			contents = contents.replace( _headRegexp, '<head><script type="text/javascript">' + JSCODE + '</script>' );
			_fileStream = new FileStream();
			_tmpFile = _appCacheFile.resolvePath( 'SWVBTmp/' + ( _tempFileCounter++) + '.' + extension );
			_fileStream.open( _tmpFile, FileMode.WRITE );
			_fileStream.writeUTFBytes( contents );
			_fileStream.close();
			return _tmpFile;
		}

		/**
		 * Creates and parses a new file with the provided contents.
		 * @param fileName the full filename in this format: "appfile:/exampledir/examplefile.html"
		 * @param contents Contents of the file.
		 * @param isHtml Boolean indicatin if file is an htmlFile ( used to inject js code in the html files );
		 */
		public static function createFile( fileName : String, contents : String, isHtml : Boolean = true ) : File
		{
			contents = parseAppFile( contents );
			if ( isHtml ) contents = contents.replace( _headRegexp, '<head><script type="text/javascript">' + JSCODE + '</script>' );
			_fileStream = new FileStream();
			_tmpFile = _appCacheFile.resolvePath( getWorkingDir() + fileName.split( 'appfile:' )[1] );
			_fileStream.open( _tmpFile, FileMode.WRITE );
			_fileStream.writeUTFBytes( contents );
			_fileStream.close();
			return _tmpFile;
		}

		/**
		 * Returns the native path for the fileName
		 * @param fileName Name of the file
		 */
		public static function getFilePath( url : String ) : String
		{
			var fileName:String = "";
			switch( true )
			{
				case url.indexOf(PROTOCOL_APP_LINK) !=-1:
					fileName = url.split( PROTOCOL_APP_LINK )[1];
					return _appCacheFile.resolvePath( getWorkingDir() + '/' + fileName ).nativePath;
				break;
				case url.indexOf(PROTOCOL_DOC_LINK) !=-1:
					fileName = url.split( PROTOCOL_DOC_LINK )[1];
					return File.documentsDirectory.resolvePath( fileName ).nativePath;
				break;
				default:
					throw new Error("StageWebViewDisk.getFilePath( url ) :: You mus provide a valid protocol applink:/ or doclink:/");	
				break;	
			}
		}



		/* STATIC EVENT DISPATCHER */
		public static function addEventListener( p_type : String, p_listener : Function, p_useCapture : Boolean = false, p_priority : int = 0, p_useWeakReference : Boolean = false ) : void
		{
			if (_disp == null)
			{
				_disp = new EventDispatcher();
			}
			_disp.addEventListener( p_type, p_listener, p_useCapture, p_priority, p_useWeakReference );
		}

		public static function removeEventListener( p_type : String, p_listener : Function, p_useCapture : Boolean = false ) : void
		{
			if (_disp == null)
			{
				return;
			}
			_disp.removeEventListener( p_type, p_listener, p_useCapture );
		}

		public static function dispatchEvent( p_event : Event ) : void
		{
			if (_disp == null)
			{
				return;
			}
			_disp.dispatchEvent( p_event );
		}




		/**
		 * Returns the Main path to the www root filesystem
		 */
		public static function getRootPath( ) : String
		{
			return _applicationRootPath;
		}

		/**
		 * Return the path of the cached files dir ( DESKTOP/ANDROID == getRootPath | iOS = "app:/www" as this uses less cache files )
		 */
		public static function getSourceRootPath() : String
		{
			return _applicationSourcesDirectory;
		}

		
		/**
		 * returns Array of current cachedExtensions
		 */
		public static function getCachedExtensions() : Array
		{
			return _cached_extensions;
		}


		/**
		 * Determines the actual working dir based on debugMode and plattform
		 */
		private static function getWorkingDir() : String
		{
			switch( true )
			{
				case isDESKTOP:
					return _debugMode ? _document_source : _document_root;
					break;
				case isIPHONE:
				case isANDROID:
					return _document_source;
					break;
			}
			return "";
		}

		/**
		 * Deletetes the Temp Directory
		 */
		private static function deleteTempFolder() : void
		{
			var tmpFile : File = _appCacheFile.resolvePath( 'SWVBTmp' );
			if ( tmpFile.exists )
			{
				tmpFile.deleteDirectory( true );
			}
		}

		/** 
		 * Parses the original files.
		 * This function executes once at app instalation or in DebugMode.
		 */
		private static function processCache() : void
		{
			dispatchEvent( new StageWebviewDiskEvent( StageWebviewDiskEvent.START_DISK_PARSING ) );
			var fileList : Vector.<File> = new Vector.<File>();
			var ext : String;


			getFilesRecursive( fileList, 'app:/' + _document_root );

			for (var e : uint = 0, totalfiles : uint = fileList.length; e < totalfiles; e++)
			{
				ext = fileList[e].extension;
				if ( _cached_extensions.indexOf( fileList[e].extension ) != -1 )
				{
					preparseFile( fileList[e] );
				}
				else
				{
					switch( true )
					{
						case isDESKTOP:
							// if debug mode copy the file to the wwwSource dir
							if ( _debugMode )
							{
								fileList[e].copyTo( _appCacheFile.resolvePath( _document_source + '/' + fileList[e].name ), true );
							}
							// else
							// Do nothing as this files are "resources" and we can reference it from its original path
							break;
						case isANDROID:
							// copy the files to the destination path, as we need a copy to reference the file
							fileList[e].copyTo( _appCacheFile.resolvePath( _document_source + '/' + fileList[e].name ), true );
							break;
						case isIPHONE:
							// Do nothing as this files are "resources" and we can reference it from its original path
							break;	
					}
				}
			}
			var firstRunFile : File = new File( _applicationCacheDirectory ).resolvePath( 'swvb.init' );
			_fileStream = new FileStream();
			_fileStream.open( firstRunFile, FileMode.WRITE );
			_fileStream.writeUTF( "init" );
			_fileStream.close();
			firstRunFile = null;
			_firstRun = false;
			dispatchEvent( new StageWebviewDiskEvent( StageWebviewDiskEvent.END_DISK_PARSING ) );
		}

		/**
		 * Parses a file contents.
		 * Injects the JS code into the local files.
		 * Replaces the appfile:/ protocol width the real path on disc
		 * 
		 * @param file File to parse
		 */
		private static function preparseFile( file : File ) : void
		{
			_copyFromFile.url = file.url;
			_copyToFile.nativePath = _appCacheFile.resolvePath( getWorkingDir() + '/' + file.url.split( 'app:/' + _document_root + '/' )[1] ).nativePath;
			// get original file contents
			_fileStream = new FileStream();
			_fileStream.open( _copyFromFile, FileMode.READ );
			var originalFileContents : String = _fileStream.readUTFBytes( _fileStream.bytesAvailable );
			_fileStream.close();

			var fileContents : String = parseAppFile( originalFileContents );
			fileContents = fileContents.split( '<head>' ).join( '<head><script type="text/javascript">' + JSCODE + '</script>' );

			// write file to the cache dir
			_fileStream = new FileStream();
			_fileStream.open( _copyToFile, FileMode.WRITE );
			_fileStream.writeUTFBytes( fileContents );
			_fileStream.close();
		}

		/**
		 * Recursively get a directory structure 
		 * @param fileList Destination vector file
		 * @param path Current path to process
		 * 
		 */
		private static function getFilesRecursive( fileList : Vector.<File>, path : String = "" ) : void
		{
			var currentFolder : File = new File( path );
			if( !currentFolder.exists ) return;
			var files : Array = currentFolder.getDirectoryListing();
			for (var f : uint = 0; f < files.length; f++)
			{
				var currFile : File = files[f];
				if (currFile.isDirectory)
				{
					if (currFile.name != "." && currFile.name != "..")
					{
						// add directory
						getFilesRecursive( fileList, currFile.url );
					}
				}
				else
				{
					// if file is not hidden add it
					if ( !currFile.isHidden ) fileList.push( currFile );
				}
			}
		}

		/**
		 * Gets a reference to the global stage
		 */
		static public function get stage() : Stage
		{
			return _stage;
		}
		
		/**
		 * Parses the provided source searching files that contains the
		 * appfile:/ protocol then changes the path according to the extension of the file.
		 */
		private static function parseAppFile( str:String ):String
		{
			// Search for files that ARE in the cached_extensions list
			// Repaces the path with a path with file:// protocol
			var result:Object = _appFileIncludeRegexp.exec(str);
			while( result != null )
			{
				str = str.replace( _appFileIncludeRegexp, _applicationRootPath+"/$2" ) ;
				result = _appFileIncludeRegexp.exec(str);
			}
			
			//Search for files that AREN'T in the cached_extensions list
			//Repaces the path with a path with file:// protocol
			str = str.split('appfile:').join( _applicationSourcesDirectory );
			return str;			
		}


	}
}
