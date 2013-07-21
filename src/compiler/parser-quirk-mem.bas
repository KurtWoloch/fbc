'' memory operations
''
'' chng: nov/2006 written [v1ctor]


#include once "fb.bi"
#include once "fbint.bi"
#include once "parser.bi"
#include once "ast.bi"

'':::::
''cOperatorNew =     NEW DataType|Constructor()
''			   |	 NEW DataType[Expr] .
''
function cOperatorNew( ) as ASTNODE ptr
	dim as integer dtype = any
	dim as FBSYMBOL ptr subtype = any, tmp = any
	dim as integer has_ctor = any, has_defctor = any, do_clear = any
	dim as ASTNODE ptr initexpr = any, elementsexpr = any, placementexpr = any
	dim as ASTNODE ptr expr = any
	dim as AST_OP op = any

	do_clear = TRUE
	op = AST_OP_NEW
	elementsexpr = NULL
	initexpr = NULL
	placementexpr = NULL

	'' NEW
	lexSkipToken( )

	'' '('?
	if( hMatch( CHAR_LPRNT ) ) then
		'' placement new
		placementexpr = cExpression( )
		if( placementexpr = NULL ) then
			errReport( FB_ERRMSG_EXPECTEDEXPRESSION, TRUE )
		end if

		'' ')'
		if( hMatch( CHAR_RPRNT ) = FALSE ) then
			errReport( FB_ERRMSG_EXPECTEDRPRNT )
		end if
	end if

	'' DataType
	hSymbolType( dtype, subtype, 0 )

	'' check for invalid types
	select case as const typeGet( dtype )
	case FB_DATATYPE_STRING, FB_DATATYPE_FIXSTR, _
	     FB_DATATYPE_CHAR, FB_DATATYPE_WCHAR
		errReport( FB_ERRMSG_NEWCANTBEUSEDWITHSTRINGS, TRUE )
		'' error recovery: fake an expr
		hSkipStmt( )
		return astNewCONSTi( 0 )
	end select

	'' Disallow creating objects of abstract classes
	hComplainIfAbstractClass( dtype, subtype )

	has_ctor = typeHasCtor( dtype, subtype )
	has_defctor = typeHasDefCtor( dtype, subtype )

	'' '['?
    if( lexGetToken( ) = CHAR_LBRACKET ) then
        lexSkipToken( )

		elementsexpr = cExpression(  )
		if( elementsexpr = NULL ) then
			errReport( FB_ERRMSG_EXPECTEDEXPRESSION )
		else
			op = AST_OP_NEW_VEC
		end if

        '' ']'
        if( lexGetToken( ) <> CHAR_RBRACKET ) then
			errReport( FB_ERRMSG_EXPECTEDRBRACKET )
			hSkipUntil( CHAR_RBRACKET )
        else
        	lexSkipToken( )
        end if

		'' '{'?
		if( lexGetToken( ) = CHAR_LBRACE ) then
			lexSkipToken( )

			'' ANY?
			if( lexGetToken( ) = FB_TK_ANY ) then
				if( has_defctor ) then
					errReportWarn( FB_WARNINGMSG_ANYINITHASNOEFFECT )
				end if
				lexSkipToken( )
				do_clear = FALSE
			else
				errReport( FB_ERRMSG_VECTORCANTBEINITIALIZED )
			end if

			'' '}'
			if( lexGetToken( ) <> CHAR_RBRACE ) then
				errReport( FB_ERRMSG_EXPECTEDRBRACE )
				'' error recovery: skip until next '}'
				hSkipUntil( CHAR_RBRACE, TRUE )
			else
				lexSkipToken( )
			end if
		end if
	end if

	'' not a vector?
	if( elementsexpr = NULL ) then
		elementsexpr = astNewCONSTi( 1, FB_DATATYPE_UINT )
	else
		'' hack(?): make sure it's a uinteger, otherwise it may crash later, fixes bug #2533376 (counting_pine)
		elementsexpr = astNewCONV( FB_DATATYPE_UINT, NULL, elementsexpr )
		if( elementsexpr = NULL ) then
			errReport( FB_ERRMSG_TYPEMISMATCH, TRUE )
			elementsexpr = astNewCONSTi( 1, FB_DATATYPE_UINT )
		end if
	end if

	'' temp pointer
	tmp = symbAddTempVar( typeAddrOf( dtype ), subtype )

	'' Constructor?
	if( has_ctor ) then
		'' '('?
		if( lexGetToken( ) = CHAR_LPRNT ) then
			'' ctor + vector? not allowed..
			if( op = AST_OP_NEW_VEC ) then
				errReport( FB_ERRMSG_EXPLICITCTORCALLINVECTOR, TRUE )
			else
				initexpr = cCtorCall( subtype )
				if( initexpr = NULL ) then
					return NULL
				end if
			end if
		else
			dim as FBSYMBOL ptr ctor = symbGetCompDefCtor( subtype )
			'' no default ctor?
			if( ctor = NULL ) then
				errReport( FB_ERRMSG_NODEFAULTCTORDEFINED )
			else
				'' only if not a vector
				if( op <> AST_OP_NEW_VEC ) then
					initexpr = cCtorCall( subtype )
					if( initexpr = NULL ) then
						return NULL
					end if
				else
					'' check visibility
					if( symbCheckAccess( ctor ) = FALSE ) then
						errReport( FB_ERRMSG_NOACCESSTODEFAULTCTOR )
					end if
				end if
			end if
		end if
	else
		'' '('?
		if( lexGetToken( ) = CHAR_LPRNT ) then
			'' vector? not allowed..
			if( op = AST_OP_NEW_VEC ) then
				errReport( FB_ERRMSG_VECTORCANTBEINITIALIZED, TRUE )
			end if

			'' ANY?
			if( lexGetLookAhead( 1 ) = FB_TK_ANY ) then
				lexSkipToken( )
				lexSkipToken( )

				do_clear = FALSE

				'' ')'
				if( lexGetToken( ) <> CHAR_RPRNT ) then
					errReport( FB_ERRMSG_EXPECTEDRPRNT )
					'' error recovery: skip until next ')'
					hSkipUntil( CHAR_RPRNT, TRUE )
				else
					lexSkipToken( )
				end if
			else
				initexpr = cInitializer( tmp, FB_INIOPT_ISINI or FB_INIOPT_DODEREF )

        		symbGetStats( tmp ) and= not FB_SYMBSTATS_INITIALIZED

				if( initexpr = NULL ) then
					errReport( FB_ERRMSG_EXPECTEDEXPRESSION )
				end if
			end if
		end if
	end if

	expr = astBuildNewOp( op, tmp, elementsexpr, initexpr, _
			dtype, subtype, do_clear, placementexpr )

	if( expr = NULL ) then
		errReport( FB_ERRMSG_INVALIDDATATYPES )
	end if

	'' return the pointer
	function = astNewLINK( expr, astNewVAR( tmp ), FALSE )
end function

'' DELETE ['[]'] expr
sub cOperatorDelete( )
	dim as ASTNODE ptr ptrexpr = any
	dim as integer dtype = any, op = any
	dim as FBSYMBOL ptr subtype = any

	'' DELETE
	lexSkipToken( )

	op = AST_OP_DEL

	'' '[' ']'?
	if( lexGetToken( ) = CHAR_LBRACKET ) then
		lexSkipToken( )
		op = AST_OP_DEL_VEC
		if( lexGetToken( ) <> CHAR_RBRACKET ) then
			errReport( FB_ERRMSG_EXPECTEDRBRACKET )
			hSkipUntil( CHAR_RBRACKET )
			return
		end if
		lexSkipToken( )
	end if

	ptrexpr = cVarOrDeref( FB_VAREXPROPT_ISEXPR )
	if( ptrexpr = NULL ) then
		errReport( FB_ERRMSG_EXPECTEDIDENTIFIER )
		hSkipStmt( )
		return
	end if

	dtype = astGetFullType( ptrexpr )
	subtype = astGetSubType( ptrexpr )

	'' not a ptr?
	if( typeIsPtr( dtype ) = FALSE ) then
		errReport( FB_ERRMSG_EXPECTEDPOINTER )
		hSkipStmt( )
		return
	end if

	dtype = typeDeref( dtype )

	select case( typeGetDtAndPtrOnly( dtype ) )
	case FB_DATATYPE_VOID
		'' Warn about ANY PTR
		errReportWarn( FB_WARNINGMSG_DELETEANYPTR )
	case FB_DATATYPE_FWDREF
		'' Disallow DELETE on forward reference ptrs
		'' (don't know whether the real type will have a dtor or not)
		errReport( FB_ERRMSG_INCOMPLETETYPE, TRUE )
		dtype = FB_DATATYPE_BYTE
	end select

	'' check visibility
	if( typeHasDtor( dtype, subtype ) ) then
		if( symbCheckAccess( symbGetCompDtor( subtype ) ) = FALSE ) then
			errReport( FB_ERRMSG_NOACCESSTODTOR )
		end if
	end if

	astAdd( astBuildDeleteOp( op, ptrexpr, dtype, subtype ) )
end sub
