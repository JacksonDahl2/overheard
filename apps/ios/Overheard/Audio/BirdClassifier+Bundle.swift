import Foundation
import OverheardKit

extension BirdClassifier {
    /// The classifier built from the model, labels, and species tables bundled in the app.
    static func bundled() throws -> BirdClassifier {
        func resource(_ name: String, _ ext: String) throws -> URL {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
                throw ClassifierError.missingResource("\(name).\(ext)")
            }
            return url
        }
        return try BirdClassifier(
            modelURL: resource("BirdNETAudio", "mlmodelc"),
            labelsURL: resource("labels", "txt"),
            filter: SpeciesFilter(
                nonBirdURL: resource("non-birds", "json"),
                speciesURL: resource("species-central-park", "json")))
    }
}
