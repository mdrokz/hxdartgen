package hxdartgen;

import haxe.macro.Expr;
import haxe.macro.Printer;

class ObjectPrinter extends Printer {

    public function new(?tabString = "\t") {
        super(tabString);
    }

    public override function printObjectFieldKey(of:ObjectField):String {
        return '"${of.field}"';
    }

    public override function printExpr(e:Expr):String {
        return switch e.expr {
            case EObjectDecl(fl):
				"{ " + fl.map(function(fld) return printObjectField(fld)).join(", ") + " }";
            
            default: ""; 
        };
    }
}