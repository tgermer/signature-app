//
//  Tip.swift
//  Signatures
//
//  Created by Tristan Germer on 04.11.24.
//

import Foundation
import TipKit

struct AddRenameTip: Tip {
    var title: Text {
        Text("Titel umbenennen")
    }
    
    var message: Text? {
        Text("Tippe auf den Titel und benenne ihn um. Danach Speichern nicht vergessen.")
    }
    
    var image: Image? {
        Image(systemName: "character.cursor.ibeam")
    }
}

struct AddNewSignatureTip: Tip {
    var title: Text {
        Text("Unterschreibe")
    }
    
    var message: Text? {
        Text("Unterschreibe auf der Hilfsline. Fange so weit wie möglich vorn an. Vermeide über den Rand hinaus zu schreiben.")
    }
    
    var image: Image? {
        Image(systemName: "signature")
    }
}
