import Foundation
func _probe() {
    func say(_ s: String) { FileHandle.standardError.write(Data((s+"\n").utf8)) }
    say("walls"); _ = TexLib.walls
    say("door"); _ = TexLib.door
    say("floor"); _ = TexLib.floor
    say("ceiling"); _ = TexLib.ceiling
    say("sprites"); let s = TexLib.sprites
    say("sprites count \(s.count)")
    say("weaponViews"); _ = TexLib.weaponViews
    say("font"); _ = Font3x5.glyphs
    say("done")
}
