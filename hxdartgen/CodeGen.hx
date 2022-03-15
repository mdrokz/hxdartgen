package hxdartgen;

import haxe.macro.Context;
import hxdartgen.Utils.CustomPrinter;
import haxe.macro.ExprTools;
import haxe.io.Path;
#if macro
import haxe.macro.Expr;
import haxe.macro.Type;
import hxdartgen.Generator;
import hxdartgen.TypeRenderer.renderClass;
import hxdartgen.TypeRenderer.renderType;
import hxdartgen.ArgsRenderer.renderArgs;
import hxdartgen.ArgsRenderer.renderConstructorArgs;

using haxe.macro.Tools;
using StringTools;

class CodeGen {
	var selector:Selector;
	var dtsDecl:Array<String>;
	var itsDecl:Array<String>;
	var etsDecl:Array<String>;
	var etsExports:Array<String>;
	var itsExports:Array<String>;

	public function new(selector:Selector) {
		this.selector = selector;
		selector.onAutoInclude = generateSome;
	}

	public function generate() {
		dtsDecl = [];
		etsDecl = Generator.GEN_ENUM_TS ? [] : dtsDecl;
		itsDecl = Generator.GEN_TYPES_DTS ? [] : dtsDecl;
		itsExports = [];
		etsExports = [];

		generateSome(selector.exposed);

		return {
			dts: dtsDecl,
			ets: etsDecl,
			its: itsDecl,
			etsExports: etsExports,
			itsExports: itsExports
		};
	}

	function generateSome(decl:Array<ExposeKind>) {
		for (e in decl) {
			switch (e) {
				case EClass(cl):
					if (cl.isInterface)
						itsDecl.push(generateClassDeclaration(cl, true));
					else
						dtsDecl.push(generateClassDeclaration(cl, true));
				case EEnum(t):
					var eDecl = generateEnumDeclaration(t, true);
					if (eDecl != "")
						etsDecl.push(eDecl);
				case ETypedef(t, anon):
					itsDecl.push(generateTypedefDeclaration(t, anon, true));
				case EMethod(cl, f):
					dtsDecl.push(generateFunctionDeclaration(cl, true, f));
			}
		}
	}

	static public function getExposePath(m:MetaAccess):Array<String> {
		return switch (m.extract(":expose")) {
			case [{params: [macro $v{(s : String)}]}]: s.split(".");
			case _: m.has(":native") ? getNativePath(m) : null;
		}
	}

	static function getNativePath(m:MetaAccess):Array<String> {
		return switch (m.extract(":native")) {
			case [{params: [macro $v{(s : String)}]}]: s.split(".");
			case _: null;
		}
	}

	static function wrapInNamespace(exposedPath:Array<String>, fn:String->String->String):String {
		#if hxtsdgen_namespaced
		var name = exposedPath.pop();
		return if (exposedPath.length == 0) fn(name, ""); else 'export namespace ${exposedPath.join(".")} {\n${fn(name, "\t")}\n}';
		#else
		return fn(exposedPath.join('_'), '');
		#end
	}

	function generateFunctionDeclaration(cl:ClassType, isExport:Bool, f:ClassField):String {
		var exposePath = getExposePath(f.meta);
		if (exposePath == null)
			exposePath = cl.pack.concat([cl.name, f.name]);

		return wrapInNamespace(exposePath, function(name, indent) {
			var parts = [];

			switch [f.kind, f.type] {
				case [FMethod(_), TFun(args, ret)]:
					var prefix = "function";
					parts.push(renderFunction(name, args, ret, f.params, indent, prefix));
				default:
					throw new Error("This kind of field cannot be exposed to JavaScript", f.pos);
			}

			return parts.join("\n");
		});
	}

	function renderFunction(name:String, args:Array<{name:String, opt:Bool, t:Type}>, ret:Type, params:Array<TypeParameter>, indent:String,
			prefix:String):String {
		var tparams = renderTypeParams(params);
		return '$indent$prefix${renderType(selector, ret)} $name$tparams(${renderArgs(selector, args)}) {}';
	}

	function renderTypeParams(params:Array<TypeParameter>):String {
		return if (params.length == 0) "" else "<" + params.map(function(t) return return t.name).join(", ") + ">";
	}

	function addEnumExportRef(exposePath:Array<String>, name:String) {
		if (Generator.GEN_ENUM_TS) {
			// this will be imported by the d.ts
			#if hxtsdgen_namespaced
			// - no package: type name
			// - with package: root package (com.foo.Bar -> com)
			if (exposePath.length == 0)
				etsExports.push(name);
			else {
				var ns = exposePath[0];
				if (etsExports.indexOf(ns) < 0)
					etsExports.push(ns);
			}
			#else
			etsExports.push(name);
			#end
		}
	}

	function addTypeExportRef(exposePath:Array<String>, name:String) {
		if (Generator.GEN_TYPES_DTS) {
			// this will be imported by the d.ts
			#if hxtsdgen_namespaced
			// - no package: type name
			// - with package: root package (com.foo.Bar -> com)
			if (exposePath.length == 0)
				itsExports.push(name);
			else {
				var ns = exposePath[0];
				if (itsExports.indexOf(ns) < 0)
					itsExports.push(ns);
			}
			#else
			itsExports.push(name);
			#end
		}
	}

	function generateClassDeclaration(cl:ClassType, isExport:Bool):String {
		var exposePath = getExposePath(cl.meta);
		if (exposePath == null)
			exposePath = cl.pack.concat([cl.name]);

		return wrapInNamespace(exposePath, function(name, indent) {
			var parts = [];

			// TODO: maybe it's a good idea to output all-static class that is not referenced
			// elsewhere as a namespace for TypeScript
			var tparams = renderTypeParams(cl.params);
			var isInterface = cl.isInterface;
			var type = 'class';
			var inherit = getInheritance(cl);
			parts.push('${indent}$type ${cl.name}$tparams$inherit {');

			{
				var indent = indent + "\t";
				if (!isInterface)
					generateConstructor(cl, isInterface, indent, parts);

				var fields = cl.fields.get();
				#if hxtsdgen_sort_fields
				fields.sort(function(a, b) {
					return a.name == b.name ? 0 : a.name < b.name ? -1 : 1;
				});
				#end
				for (field in fields)
					if (field.isPublic || isPropertyGetterSetter(fields, field))
						addField(field, false, isInterface, indent, parts);

				fields = cl.statics.get();
				for (field in fields)
					if (field.isPublic || isPropertyGetterSetter(fields, field))
						addField(field, true, isInterface, indent, parts);
			}

			if (isInterface && isExport) {
				addTypeExportRef(exposePath, name);
			}

			parts.push('$indent}');
			return parts.join("\n");
		});
	}

	function getInheritance(t:ClassType) {
		var sup = t.superClass;
		var ext = '';
		if (sup != null) {
			var cl = sup.t.get();
			ext = ' extends ${renderClass(selector, cl)}';
		}
		var ints = '';
		if (t.interfaces != null && t.interfaces.length > 0) {
			var names = t.interfaces.map(function(item) {
				var cl = item.t.get();
				return '${renderClass(selector, cl)}';
			});
			if (t.isInterface)
				ints = ' extends ${names.join(', ')}';
			else
				ints = ' implements ${names.join(', ')}';
		}
		return '$ext$ints';
	}

	function generateEnumDeclaration(t:ClassType, isExport:Bool):String {
		// TypeScript `const enum` are pure typing constructs (e.g. don't exist in JS either)
		// so it matches Haxe abstract enum well.

		// Unwrap abstract type
		var bt:BaseType = t;
		switch (t.kind) {
			case KAbstractImpl(_.get() => at):
				bt = at;
			default: // we keep what we have
		}

		var exposePath = getExposePath(t.meta);
		if (exposePath == null)
			exposePath = bt.pack.concat([bt.name]);

		return wrapInNamespace(exposePath, function(name, indent) {
			var parts = [];

			parts.push('${indent} enum $name {');

			{
				var indent = indent + "\t";
				var added = 0;
				var fields = t.statics.get();
				for (field in fields)
					if (field.isPublic)
						added += addConstValue(field, indent, parts) ? 1 : 0;
				if (added == 0)
					return ""; // empty enum
			}

			if (isExport)
				addEnumExportRef(exposePath, name);

			parts.push('$indent}');
			return parts.join("\n");
		});
	}

	function generateTypedefDeclaration(t:DefType, anon:AnonType, isExport:Bool):String {
		var exposePath = getExposePath(t.meta);
		if (exposePath == null)
			exposePath = t.pack.concat([t.name]);

		var parts = [];

		var tparams = renderTypeParams(t.params);
		parts.push('class ${t.name}$tparams {');

		{
			var indent = "\t";
			var fields = anon.fields;
			for (field in fields)
				addField(field, false, true, indent, parts);
		}

		if (isExport)
			addTypeExportRef(exposePath, t.name);

		parts.push('}');
		return parts.join("\n");
	}

	function addConstValue(field:ClassField, indent:String, parts:Array<String>) {
		switch (field.kind) {
			case FVar(_, _):
				var expr = field.expr().expr;
				var value = switch (expr) {
					case TCast(_.expr => TConst(c), _):
						switch (c) {
							case TInt(v): Std.string(v);
							case TFloat(f): Std.string(f);
							case TString(s): '"${escapeString(s)}"';
							case TNull: null; // not allowed
							case TBool(_): null; // not allowed
							default: null;
						}
					default: null;
				};
				if (value != null) {
					parts.push('$indent${field.name} = $value,');
					return true;
				}
			default:
		}
		return false;
	}

	function escapeString(s:String) {
		return s.split('\\').join('\\\\').split('"').join('\\"');
	}

	function addField(field:ClassField, isStatic:Bool, isInterface:Bool, indent:String, parts:Array<String>) {
		var prefix = if (isStatic) "static " else "";
		var printer = new CustomPrinter();

		switch [field.kind, field.type] {
			case [FMethod(_), TFun(args, ret)]:
				parts.push(renderFunction(field.name, args, ret, field.params, indent, prefix));

			case [FVar(read, write), _]:
				switch (write) {
					case AccNo | AccNever | AccCall:
						prefix += "final";
					default:
				}
				if (read != AccCall) {
					var option = isInterface && isNullable(field) ? "?" : "";

					var field_var = field.meta.get()[0];

					// trace(Context.follow(field.type));

					if (Reflect.field(field_var, "params") != null) {
						var fieldExpr = field_var.params[0];

						switch fieldExpr.expr {
							case EObjectDecl(_): {
									var x = printer.printExpr(fieldExpr);

									parts.push(' var $indent$prefix${field.name}$option = $x;');
								}
							default: {
									var x = printer.printExpr(fieldExpr);
									parts.push('$indent$prefix ${renderType(selector, field.type)} ${field.name}$option = $x;');
								}
						}
					} else {
						parts.push('late$indent$prefix ${renderType(selector, field.type)} ${field.name};');
					}
				}

			default:
		}
	}

	function generateConstructor(cl:ClassType, isInterface:Bool, indent:String, parts:Array<String>) {
		// Heads up! constructors never declared as private since that will prevent inheritance in TS
		// but haxe allows to extend a class even if it has a single explicitly private constructor.
		// Example: `class haxe.io.BytesInput extends haxe.io.InputExample`
		var privateCtor = true;
		if (cl.constructor != null) {
			var ctor = cl.constructor.get();
			privateCtor = false;
			switch (ctor.type) {
				case TFun(args, _):
					var prefix = "";
					var constructor = '${indent}${prefix}${cl.name}';

					var expr = ctor.expr();

					var x = ExprTools.toString(Context.getTypedExpr(expr));

					constructor += if (args.length > 0) '({${renderConstructorArgs(selector, args)}}) {${x}}' else '() {}';

					// parts.push('${indent}${prefix}${cl.name}({${renderConstructorArgs(selector, args)}}) {}');
					parts.push(constructor);
				default:
					throw 'Invalid constructor type ${ctor.type.toString()}';
			}
		} else if (!isInterface) {
			parts.push('${indent} ${cl.name}();');
		}
	}

	// For a given `method` looking like a `get_x`/`set_x`, look for a matching property
	function isPropertyGetterSetter(fields:Array<ClassField>, method:ClassField) {
		var re = new EReg('(get|set)_(.*)', '');
		if (re.match(method.name)) {
			var name = re.matched(2);
			for (field in fields)
				if (field.name == name && isProperty(field))
					return true;
		}
		return false;
	}

	function isProperty(field) {
		return switch (field.kind) {
			case FVar(read, write): write == AccCall || read == AccCall;
			default: false;
		};
	}

	function renderGetter(field:ClassField, indent:String, prefix:String) {
		return renderFunction('get_${field.name}', [], field.type, field.params, indent, prefix);
	}

	function renderSetter(field:ClassField, indent:String, prefix:String) {
		var args = [
			{
				name: 'value',
				opt: false,
				t: field.type
			}
		];
		return renderFunction('set_${field.name}', args, field.type, field.params, indent, prefix);
	}

	function isNullable(field:ClassField) {
		return switch (field.type) {
			case TType(_.get() => _.name => 'Null', _): true;
			default: false;
		}
	}
}
#end
