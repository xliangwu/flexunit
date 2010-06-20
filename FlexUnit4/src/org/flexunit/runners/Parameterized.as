/**
 * Copyright (c) 2009 Digital Primates IT Consulting Group
 * 
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 * 
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 * 
 * @author     Alan Stearns - astearns@adobe.com
 * 			   Michael Labriola - labriola@digitalprimates.net
 * 			   David Wolever - david@wolever.net
 * @version
 *   
 **/

package org.flexunit.runners
{	
	import flex.lang.reflect.Field;
	
	import org.flexunit.constants.AnnotationConstants;
	import org.flexunit.internals.dependency.ExternalDependencyResolver;
	import org.flexunit.internals.dependency.IExternalDependencyResolver;
	import org.flexunit.internals.dependency.IExternalRunnerDependencyWatcher;
	import org.flexunit.internals.runners.ErrorReportingRunner;
	import org.flexunit.internals.runners.InitializationError;
	import org.flexunit.internals.runners.statements.IAsyncStatement;
	import org.flexunit.runner.IDescription;
	import org.flexunit.runner.IRunner;
	import org.flexunit.runner.external.IExternalDependencyRunner;
	import org.flexunit.runner.notification.IRunNotifier;
	import org.flexunit.runner.notification.StoppedByUserException;
	import org.flexunit.runners.model.FrameworkMethod;
	import org.flexunit.runners.model.IRunnerBuilder;
	import org.flexunit.token.AsyncTestToken;
	
	public class Parameterized extends ParentRunner implements IExternalDependencyRunner {

		/**
		 * @private
		 */
		private var runners:Array;
		/**
		 * @private
		 */
		private var klass:Class;
		/**
		 * @private
		 */
		private var dr:IExternalDependencyResolver;
		/**
		 * @private
		 */
		private var _dependencyWatcher:IExternalRunnerDependencyWatcher;
		/**
		 * @private
		 */
		private var dependencyDataWatchers:Array;
		/**
		 * @private
		 */
		private var _externalDependencyError:String;
		/**
		 * @private
		 */
		private var externalError:Boolean = false;

		/**
		 * Setter for a dependency watcher. This is a class that implements IExternalRunnerDependencyWatcher
		 * and watches for any external dependencies (such as loading data) are finalized before execution of
		 * tests is allowed to commence.  
		 * 		 
		 * @param value An implementation of IExternalRunnerDependencyWatcher
		 */
		public function set dependencyWatcher( value:IExternalRunnerDependencyWatcher ):void {
			_dependencyWatcher = value;
			
			if ( value && dr ) {
				value.watchDependencyResolver( dr );	
			}
		}
		
		/**
		 * 
		 * Setter to indicate an error occured while attempting to load exteranl dependencies
		 * for this test. It accepts a string to allow the creator of the external dependency
		 * loader to pass a viable error string back to the user.
		 * 
		 * @param value The error message
		 * 
		 */
		public function set externalDependencyError( value:String ):void {
			externalError = true;
			_externalDependencyError = value;
		}
		
		/**
		 * Constructor.
		 * 
		 * @param klass The test class that is to be executed by the runner.
		 */
		public function Parameterized(klass:Class) {
			super(klass);
			this.klass = klass;
			
			dr = new ExternalDependencyResolver( klass, this );
			dr.resolveDependencies();
		}

		/**
		 * @private
		 */
		private function buildErrorRunner( message:String ):Array {
			return [new ErrorReportingRunner( klass, new Error("There was an error retrieving the parameters for the testcase: cause " + message ) ) ];			
		}

		/**
		 * @private
		 */
		private function buildRunners():Array {
			var runners:Array = new Array();

			try {
				var parametersList:Array = getParametersList(klass);
				if ( parametersList.length == 0 ) {
					runners.push(new TestClassRunnerForParameters(klass));
				} else {
					for (var i:int= 0; i < parametersList.length; i++) {
						runners.push(new TestClassRunnerForParameters(klass,parametersList, i));
					}
				}
			}
			
			catch ( error:Error ) {
				runners = buildErrorRunner( error.message );
			}
			
			return runners;
		}
		
		/**
		 * @private
		 */
		private function getParametersList(klass:Class):Array {
			var allParams:Array = new Array();
			var frameworkMethod:FrameworkMethod;
			var field:Field;
			var methods:Array = getParametersMethods(klass);
			var fields:Array = getParametersFields(klass);
			var data:Array;

			for ( var i:int=0; i<methods.length; i++ ) {
				frameworkMethod = methods[ i ];
				
				data = frameworkMethod.invokeExplosively(klass) as Array;
				allParams = allParams.concat( data );
			}

			for ( var j:int=0; j<fields.length; j++ ) {
				field = fields[ j ];
				
				data = field.getObj( null ) as Array;
				allParams = allParams.concat( data );
			}
			
			return allParams;
		}
		
		/**
		 * @private
		 */
		private function getParametersMethods(klass:Class):Array {
			var methods:Array = testClass.getMetaDataMethods( AnnotationConstants.PARAMETERS );
			return methods;
		}

		/**
		 * @private
		 */
		private function getParametersFields(klass:Class):Array {
			var fields:Array = testClass.getMetaDataFields( AnnotationConstants.PARAMETERS, true );
			return fields;
		}

		/**
		 * @inheritDoc
		 */
		override protected function get children():Array {
			if ( !runners ) {
				if ( !externalError ) {
					runners = buildRunners();	
				} else {
					runners = buildErrorRunner( _externalDependencyError );
				}
			}

			return runners;
		}

		/**
		 * @inheritDoc
		 */
		override protected function describeChild( child:* ):IDescription {
			return IRunner( child ).description;
		}

		/**
		 * @inheritDoc
		 */
		override public function pleaseStop():void {
			super.pleaseStop();
			
			if ( runners ) {
				for ( var i:int=0; i<runners.length; i++ ) {
					( runners[ i ] as IRunner ).pleaseStop(); 
				}
			}
		}
		
		/**
		 * @inheritDoc
		 */
		override protected function runChild( child:*, notifier:IRunNotifier, childRunnerToken:AsyncTestToken ):void {
			if ( stopRequested ) {
				childRunnerToken.sendResult( new StoppedByUserException() );
				return;
			}
			
			IRunner( child ).run( notifier, childRunnerToken );
		}
		// end Items copied from Suite
	}
}

import flex.lang.reflect.Field;
import flex.lang.reflect.Klass;
import flex.lang.reflect.Method;
import flex.lang.reflect.metadata.MetaDataAnnotation;
import flex.lang.reflect.metadata.MetaDataArgument;

import org.flexunit.constants.AnnotationArgumentConstants;
import org.flexunit.constants.AnnotationConstants;
import org.flexunit.internals.runners.InitializationError;
import org.flexunit.internals.runners.statements.IAsyncStatement;
import org.flexunit.runner.Description;
import org.flexunit.runner.IDescription;
import org.flexunit.runner.notification.IRunNotifier;
import org.flexunit.runners.BlockFlexUnit4ClassRunner;
import org.flexunit.runners.model.FrameworkMethod;
import org.flexunit.runners.model.ParameterizedMethod;
import org.flexunit.token.AsyncTestToken;
	
class TestClassRunnerForParameters extends BlockFlexUnit4ClassRunner {
	/**
	 * @private
	 */
	private var klassInfo:Klass;
	/**
	 * @private
	 */
	private var expandedTestList:Array;
	/**
	 * @private
	 */
	private var parameterSetNumber:int;
	/**
	 * @private
	 */
	private var parameterList:Array;
	/**
	 * @private
	 */
	private var constructorParameterized:Boolean = false;
	
	/**
	 * @private
	 */
	private function buildExpandedTestList():Array {
		var testMethods:Array = testClass.getMetaDataMethods( AnnotationConstants.TEST );
		var finalArray:Array = new Array();
		
		for ( var i:int=0; i<testMethods.length; i++ ) {
			var fwMethod:FrameworkMethod = testMethods[ i ];
			var argument:MetaDataArgument = fwMethod.method.getMetaData( AnnotationConstants.TEST ).getArgument( AnnotationArgumentConstants.DATAPROVIDER );
			var classMethod:Method;
			var field:Field;
			var results:Array;
			var paramMethod:ParameterizedMethod;
			
			if ( argument ) {
				classMethod = klassInfo.getMethod( argument.value ); 
				
				if ( classMethod ) {
					results = classMethod.invoke( testClass ) as Array;
				} else {
					field = klassInfo.getField( argument.value );
					
					if ( field ) {
						var ar:Array = field.getObj(null) as Array;
						results = new Array();
						results = results.concat( ar );
					}
				}
				
				var methodXML : XML = insertOrderMetadataIfNecessary( fwMethod.method );
				
				for ( var j:int=0; j<results.length; j++ ) {
					var method:Method = applyOrderToParameterizedTestMethod( methodXML, j, results.length );
					paramMethod = new ParameterizedMethod( method, results[ j ] );
					finalArray.push( paramMethod ); 	
				}
			} else {
				finalArray.push( fwMethod );
			}
		}
		
		return finalArray;
	}

	/**
	 * 
	 * @param method Method currently under test
	 * @return an XML clone of this method with Order metadata inserted
	 * 
	 */
	protected function insertOrderMetadataIfNecessary( method : Method ) : XML
	{
		var xmlCopy:XML = method.methodXML.copy();
		
		var a:MetaDataAnnotation = method.getMetaData( AnnotationConstants.TEST );
		var arg:MetaDataArgument;
		
		if ( a )
			arg = a.getArgument( AnnotationArgumentConstants.ORDER );
		else	// CJP: If the method doesn't contain a "TEST" metadata tag, we probably shouldn't be in  here anyway... throw Error?
			return xmlCopy;
		
		if ( !arg )
			xmlCopy.metadata.(@name=="Test").appendChild( <arg key="order" value="0"/> );
		
		return xmlCopy;
	}
	
	/**
	 * 
	 * Returns a new method with order metadata injected to ensure parameters run in an expected order
	 * 
	 * @param methodXML an XML descriptor of the method
	 * @param dataSetIndex an index into the data being applied to the method
	 * @param totalMethods the total number of methods expanded by this dataprovider
	 * @return a new Method
	 * 
	 */
	protected function applyOrderToParameterizedTestMethod( methodXML : XML, dataSetIndex : int, totalMethods : int ) : Method
	{
		var xmlCopy:XML = methodXML.copy();
		
		var orderValueDec : Number = (dataSetIndex + 1) / ( Math.pow( 10, totalMethods ) );
		var newOrderValue : Number = xmlCopy.metadata.(@name=="Test").arg.( @key == "order" ).attribute( "value" ) + orderValueDec;
		
		xmlCopy.metadata.(@name=="Test").arg.( @key == "order" ).( @value = newOrderValue );
		var newMethod:Method = new Method( xmlCopy );
		return newMethod;
	}
	
	/**
	 * @inheritDoc
	 */
	override protected function computeTestMethods():Array {
		//OPTIMIZATION POINT		
		if ( !expandedTestList ) {
			expandedTestList = buildExpandedTestList();
		}

		return expandedTestList; 
	}
	
	/**
	 * @inheritDoc
	 */
	override protected function validatePublicVoidNoArgMethods( metaDataTag:String, isStatic:Boolean, errors:Array ):void {
		
		//Only validate the ones that do not have a dataProvider attribute for these rules
		var methods:Array = testClass.getMetaDataMethods( metaDataTag  );
		var annotation:MetaDataAnnotation;
		var argument:MetaDataArgument;
		
		var eachTestMethod:FrameworkMethod;
		for ( var i:int=0; i<methods.length; i++ ) {
			eachTestMethod = methods[ i ] as FrameworkMethod;
			
			annotation = eachTestMethod.method.getMetaData( AnnotationConstants.TEST );
			
			if ( annotation ) {
				//Does it have a dataProvider?
				argument = annotation.getArgument( AnnotationArgumentConstants.DATAPROVIDER );
			}
			
			//If there is an argument, we need to punt on verification of arguments until later when we know how many there actually are
			if ( !argument ) {
				eachTestMethod.validatePublicVoidNoArg( isStatic, errors );
			} 
		}
	}
	
	/**
	 * @inheritDoc
	 */
	override protected function describeChild( child:* ):IDescription {
		if ( !constructorParameterized ) {
			return super.describeChild( child );
		}
		
		var params:Array = computeParams();
		
/*		if ( !params ) {
			throw new InitializationError( "Parameterized runner has not been provided data" );
		}*/

		var paramName:String = params?params.join ( "_" ):"Missing Params";
		var method:FrameworkMethod = FrameworkMethod( child );
		return Description.createTestDescription( testClass.asClass, method.name + '_' + paramName, method.metadata );
	}


	/**
	 * @private
	 */
	private function computeParams():Array {
		return parameterList?parameterList[parameterSetNumber]:null;
	}

	/**
	 * 
	 * Creates a new instance of the test with possible arguments
	 * 
	 * @return A new instance of the test case being tested 
	 * 
	 */	
	override protected function createTest():Object {
		var args:Array = computeParams();
		
		if ( args && args.length > 0 ) {
			return testClass.klassInfo.constructor.newInstanceApply( args );	
		} else {
			return testClass.klassInfo.constructor.newInstance();
		}
	}

	//we don't want the BeforeClass and AfterClass on this run to execute, this will be handled by Parameterized
	/**
	 * @inheritDoc
	 */
	override protected function classBlock( notifier:IRunNotifier ):IAsyncStatement {
		return childrenInvoker( notifier );
	}

	/**
	 * Constructor.
	 * 
	 * @param klass The test class that is to be executed by the runner.
	 * @param parameterList Array of parameters to be applied to methods
	 * @param i an index into the parameterList Array for the current parameter set
	 */
	public function TestClassRunnerForParameters(klass:Class, parameterList:Array=null, i:int=0) {
		klassInfo = new Klass( klass );
		super(klass);
		
		this.parameterList = parameterList;
		this.parameterSetNumber = i;
		
		if ( parameterList && parameterList.length > 0 ) {
			constructorParameterized = true;
		}
	}
}
