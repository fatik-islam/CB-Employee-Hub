import CoreLocation
import Foundation

struct LocationSnapshot: Sendable {
    let latitude,longitude,accuracy:Double
    let isSimulated,isProducedByAccessory:Bool
}

@MainActor final class LocationService:NSObject,CLLocationManagerDelegate {
    private let manager=CLLocationManager(); private var continuation:CheckedContinuation<LocationSnapshot?,Never>?
    override init(){super.init();manager.delegate=self;manager.desiredAccuracy=kCLLocationAccuracyBest;manager.distanceFilter=kCLDistanceFilterNone}
    func current() async -> LocationSnapshot? { if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() };return await withCheckedContinuation{continuation=$0;manager.requestLocation()} }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]){guard let latest=locations.filter({$0.horizontalAccuracy>=0}).min(by:{$0.horizontalAccuracy<$1.horizontalAccuracy}) else{return};continuation?.resume(returning:LocationSnapshot(latitude:latest.coordinate.latitude,longitude:latest.coordinate.longitude,accuracy:latest.horizontalAccuracy,isSimulated:latest.sourceInformation?.isSimulatedBySoftware ?? false,isProducedByAccessory:latest.sourceInformation?.isProducedByAccessory ?? false));continuation=nil}
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error){continuation?.resume(returning:nil);continuation=nil}
}
