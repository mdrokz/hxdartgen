@:expose('me')
class Meow {
    var v = 0;
    var v1 = 1;
    var v3 = 2;

    public function new() {}
}

@:expose('heck')
class Main {
    final m: Meow = new Meow();
    public static function main() {
        trace('hello');
    }
}