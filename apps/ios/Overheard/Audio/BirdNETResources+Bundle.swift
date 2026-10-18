import Foundation
import OverheardKit

extension BirdNETResources {
    /// The models and species catalog bundled in the app.
    static func bundled() throws -> BirdNETResources {
        func resource(_ name: String, _ ext: String) throws -> URL {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
                throw ClassifierError.missingResource("\(name).\(ext)")
            }
            return url
        }
        return try BirdNETResources(
            audioModel: resource("BirdNETAudio", "mlmodelc"),
            locationModel: resource("BirdNETMeta", "mlmodelc"),
            catalog: resource("species", "json"))
    }
}
