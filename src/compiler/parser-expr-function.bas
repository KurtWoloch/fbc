'' function call parsing
''
'' chng: sep/2004 written [v1ctor]


#include once "fb.bi"
#include once "fbint.bi"
#include once "parser.bi"
#include once "ast.bi"

'':::::
#macro hParseRPNT( )
	if( lexGetToken( ) <> CHAR_RPRNT ) then
		errReport( FB_ERRMSG_EXPECTEDRPRNT )
		'' error recovery: skip until next ')'
		hSkipUntil( CHAR_RPRNT, TRUE )
	else
		lexSkipToken( )
	end if
#endmacro

'':::::
function cFunctionCall _
	( _
		byval base_parent as FBSYMBOL ptr, _
		byval sym as FBSYMBOL ptr, _
		byval ptrexpr as ASTNODE ptr, _
		byval thisexpr as ASTNODE ptr, _
		byval options as FB_PARSEROPT _
	) as ASTNODE ptr

	dim as ASTNODE ptr funcexpr = any
	dim as FB_CALL_ARG_LIST arg_list = ( 0, NULL, NULL )

	function = NULL

    if( sym = NULL ) then
    	exit function
    end if

	options or= FB_PARSEROPT_ISFUNC

    hMethodCallAddInstPtrOvlArg( sym, thisexpr, @arg_list, @options )

	'' property?
	if( symbIsProperty( sym ) ) then

		options or= FB_PARSEROPT_ISPROPGET

		'' '('? indexed..
		if( lexGetToken( ) = CHAR_LPRNT ) then
			if( symbGetUDTHasIdxGetProp( symbGetParent( sym ) ) = FALSE ) then
				errReport( FB_ERRMSG_PROPERTYHASNOIDXGETMETHOD, TRUE )
			end if

			lexSkipToken( )

			funcexpr = cProcArgList( base_parent, sym, ptrexpr, @arg_list, options )
			if( funcexpr = NULL ) then
				exit function
			end if

			'' ')'
			hParseRPNT( )

		'' not indexed..
		else
			if( symbGetUDTHasGetProp( symbGetParent( sym ) ) = FALSE ) then
				errReport( FB_ERRMSG_PROPERTYHASNOGETMETHOD )
			end if

			'' no args
			funcexpr = cProcArgList( base_parent, _
									 sym, _
									 ptrexpr, _
									 @arg_list, _
									 options or FB_PARSEROPT_OPTONLY )
			if( funcexpr = NULL ) then
				exit function
			end if
		end if

	else
		'' '('?
		if( lexGetToken( ) = CHAR_LPRNT ) then
			lexSkipToken( )

			'' ProcArgList
			funcexpr = cProcArgList( base_parent, sym, ptrexpr, @arg_list, options )
			if( funcexpr = NULL ) then
				exit function
			end if

			'' ')'
			hParseRPNT( )

		else
			'' ProcArgList (function could have optional params)
			funcexpr = cProcArgList( base_parent, _
									 sym, _
									 ptrexpr, _
									 @arg_list, _
									 options or FB_PARSEROPT_OPTONLY )
			if( funcexpr = NULL ) then
				exit function
			end if
		end if

	end if

	'' is it really a function?
	if( astGetDataType( funcexpr ) = FB_DATATYPE_VOID ) then
		errReport( FB_ERRMSG_SYNTAXERROR )
		'' error recovery: remove the SUB call, return a fake node
		astDelTree( funcexpr )
		return astNewCONSTi( 0 )
	end if

	'' Take care of functions returning BYREF
	funcexpr = astBuildByrefResultDeref( funcexpr )

	''
	function = cStrIdxOrMemberDeref( funcexpr )
end function

'':::::
''Function        =   ID ('(' ProcParamList ')')? FuncPtrOrMemberDeref? .
''
function cFunctionEx _
	( _
		byval base_parent as FBSYMBOL ptr, _
		byval sym as FBSYMBOL ptr, _
		byval options as FB_PARSEROPT _
	) as ASTNODE ptr

	'' ID
	lexSkipToken( )

	function = cFunctionCall( base_parent, sym, NULL, NULL, options )

end function

'':::::
function cMethodCall _
	( _
		byval sym as FBSYMBOL ptr, _
		byval thisexpr as ASTNODE ptr, _
		byval options as FB_PARSEROPT _
	) as ASTNODE ptr

	dim as ASTNODE ptr expr = any

	'' ID
	lexSkipToken( )

	'' inside an expression? (can't check sym type, it could be an overloaded proc)
	if( fbGetIsExpression( ) ) then
		expr = cFunctionCall( NULL, sym, NULL, thisexpr, options )

		'' no need to check expr, cFunctionCall() will handle VOID calls

	'' assignment..
	else
		expr = cProcCall( NULL, sym, NULL, thisexpr, FALSE, options )

		'' ditto
	end if

	function = expr

end function

'':::::
function cCtorCall _
	( _
		byval sym as FBSYMBOL ptr _
	) as ASTNODE ptr

	dim as FBSYMBOL ptr tmp = any
	dim as integer isprnt = any
	dim as ASTNODE ptr procexpr = any
	dim as FB_CALL_ARG_LIST arg_list = ( 0, NULL, NULL )

	'' alloc temp var
	tmp = symbAddTempVar( symbGetType( sym ), sym )
	astDtorListAdd( tmp )

	'' '('?
	if( lexGetToken( ) = CHAR_LPRNT ) then
		lexSkipToken( )
		isprnt = TRUE
	else
		isprnt = FALSE
	end if

    '' pass the instance ptr
	dim as FB_CALL_ARG ptr arg = symbAllocOvlCallArg( @parser.ovlarglist, @arg_list, FALSE )
	arg->expr = astNewVAR( tmp )
	arg->mode = INVALID

	procexpr = cProcArgList( NULL, _
							 symbGetCompCtorHead( sym ), _
					  		 NULL, _
					  		 @arg_list, _
					  		 FB_PARSEROPT_ISFUNC or _
					  		 FB_PARSEROPT_HASINSTPTR or _
					  		 iif( isprnt = FALSE, _
					  		 	  FB_PARSEROPT_OPTONLY, _
					  		 	  FB_PARSEROPT_NONE ) )

	'' Try to parse the ')' even in case of error recovery; it belongs to
	'' the type() construct afterall, and nothing else would handle it.

	if( isprnt ) then
		'' ')'?
		if( lexGetToken( ) <> CHAR_RPRNT ) then
			errReport( FB_ERRMSG_EXPECTEDRPRNT )
			'' error recovery: skip until next ')'
			hSkipUntil( CHAR_RPRNT, TRUE )
		else
			lexSkipToken( )
		end if
	end if

	'' cProcArgList() usually returns a CALL, but it can be NULL or a CONST
	'' etc. in case of error recovery
	if( procexpr = NULL ) then
		function = NULL
	elseif( astIsCALL( procexpr ) = FALSE ) then
		function = procexpr
	else
		function = astNewCALLCTOR( procexpr, astNewVAR( tmp ) )
	end if
end function
