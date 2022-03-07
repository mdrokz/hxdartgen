import haxe.macro.ExprTools;
import haxe.macro.Expr.Binop;

@:expose()
class Meow {
	public var v = 100;

	var v1 = 1;
	var v3 = 2;

	public var c = {
		c: 0
	};

	public function new(v:Int) {
		//    trace('hello');
		var x = 1;
		this.c = {
			c: 3
		};
		this.c = {
			c: 4
		};
		this.v3 = 100;
	}
}

@:expose()
class Main {
	@:expose
	final m:Meow = new Meow(3);

	public static function main() {
		var x = macro {
			var c = 0;
			var ff = 0;
			this.s = 3;
			this.x = 4;
		}

		trace(x);

		switch x.expr {
			case EBlock(a):
				{
					for (e in a) {
						switch e.expr {
							case EVars(vars): {
									var name = vars[0].name;
									var vexpr = vars[0].expr;
									trace(name);
								}

							case EBinop(op,e1,e2): {
								trace(op,ExprTools.toString(e1),ExprTools.toString(e2));
							}	
							default:
						}
					}
				}

			default:
		}
		trace('hello');
	}
}
