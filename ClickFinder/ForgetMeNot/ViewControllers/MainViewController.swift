//
//  MainViewController.swift
//  clickFinder
//
//  Created by Ivan Pavic on 30.03.19.
//  Copyright © 2019 Ray Wenderlich. All rights reserved.
//

import Foundation
import UIKit
import WebKit
import CoreLocation
import FirebaseDatabase
import FirebaseAuth
import Firebase
import Alamofire
import FirebaseInstanceID

let storedItemsKey = "storedItems"

//extends itemsviewcontroller functionalities
extension MainViewController: CLLocationManagerDelegate {
    
    func setUpLocationManager(){
        //prompt the user for access to location services if they haven’t granted it already
        locationManager.requestAlwaysAuthorization()
        
        AppConstants.region.notifyOnEntry = true;
        AppConstants.region.notifyOnExit = true;
        AppConstants.region.notifyEntryStateOnDisplay = true;
        
        //This sets the CLLocationManager delegate to self so you’ll receive delegate callbacks.
        if CLLocationManager.locationServicesEnabled() && CLLocationManager.isRangingAvailable() && CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self) {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
        }
    }
    
    func start(){
        locationManager.startUpdatingLocation()
        locationManager.startMonitoring(for: AppConstants.region)
        locationManager.startRangingBeacons(in: AppConstants.region)
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        //ivc.loadItems()
//        let userDefaults = UserDefaults.standard
//        let decoded  = userDefaults.data(forKey: storedItemsKey)
//        ivc.items = NSKeyedUnarchiver.unarchiveObject(with: decoded!) as! [Item]
//
//        print("DECODED")
//        for item in ivc.items {
//            printItem(item: item)
//        }
        
        notificationPublisher.sendNotification(
            title: "Entered region",
            subtitle: region.identifier,
            body: "This is a background test local notification",
            badge: 1,
            delayInterval: nil,
            identifier: "exit notification"
        )
        
        print("Entered region")
        
        //locationManager.startUpdatingLocation()
        locationManager.startRangingBeacons(in: AppConstants.region)
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        notificationPublisher.sendNotification(
            title: "Left region",
            subtitle: region.identifier,
            body: "This is a background test local notification",
            badge: 1,
            delayInterval: nil,
            identifier: "exit notification"
        )
        
        print("Left region")
        
        //locationManager.stopUpdatingLocation()
        locationManager.stopRangingBeacons(in: AppConstants.region)
    }
    
    func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        print("ranging")
        
        //Handling of the found beacons
        for beacon in beacons {
            if ivc.items.isEmpty {
                print("Unknown iBeacon found")
                handleUnknownIBeacons(beacon: beacon)
            }else{
                if let item = ivc.items.first(where:{$0.majorValue == UInt16(truncating: beacon.major) && $0.minorValue == UInt16(truncating: beacon.minor)}){
                    item.beacon = beacon
                    
                    let endDate = Date()
                    let elapsed = Int(endDate.timeIntervalSince(toastStartDate))
                    if checkIfActive(){
                        if elapsed > 5{
                            showToast(message: "\(item.name) \n\(item.nameForProximity(beacon.proximity))")
                            toastStartDate = Date()
                        }
                    }else {
                        checkIfLost(item: item, known: true)
                    }
                } else {
                    print("Unknown iBeacon found")
                    handleUnknownIBeacons(beacon: beacon)
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let locValue: CLLocationCoordinate2D = manager.location?.coordinate else { return }
        
        self.currentLocation.latitude = locValue.latitude
        self.currentLocation.longitude = locValue.longitude
        //print(locValue.latitude)
        //print(locValue.longitude)
    }
    
    private func handleUnknownIBeacons(beacon: CLBeacon){
        var newBeacon : CLBeacon?
        
        //major value > 32000 -> the pairing button has been pressed
        if Int(truncating: beacon.major) > 32000{
            print("Pairing iBeacon found")
            newBeacon = beacon
        } else {
            let item = Item(name: "New", icon: 4, uuid: beacon.proximityUUID, majorValue: Int(truncating: beacon.major), minorValue: Int(truncating: beacon.minor))
            let endDate = Date()
            let elapsed = Int(endDate.timeIntervalSince(startDate))
            
            //print("\(elapsed) + \(beacon.major) + \(beacon.minor)")
            
            if  elapsed > 60 { // delay to avoid backend overloading
                //print("alreadyRangedItems array cleaned")
                startDate = Date()
                alreadyRangedItems.removeAll(keepingCapacity: false)
            }
            
            var found = false
            for itemN in alreadyRangedItems{
                if ( (itemN.majorValue == item.majorValue) && (itemN.minorValue == item.minorValue) ){
                    found = true
                }
            }
            
            if found == false{
                alreadyRangedItems.append(item)
                print(alreadyRangedItems)
                
                checkIfLost(item: item, known: false)
            }
        }
        
        print(pairingIsOn)
        
        if pairingIsOn == true {
            print("Pairing the new iBeacon")
            if(newBeacon != nil){
                self.pairingIsOn = false
                
                let major = Int(truncating: newBeacon!.major)-32000 //Pairing done
                
                let item = Item(name: "New", icon: 4, uuid: newBeacon!.proximityUUID, majorValue: major, minorValue: Int(truncating: newBeacon!.minor))
                
                var flag = false
                
                for itemN in ivc.items{
                    if ( (itemN.majorValue == item.majorValue) && (itemN.minorValue == item.minorValue) ){
                        flag = true
                    }
                }
                
                if flag == false{
                    print("ALERT")
                    createAlert(title: "New beacon found!", message: itemAsString(item: item), item: item)
                }
                
                flag = true
            }
            
        }
    }
    
    private func locationManager(manager: CLLocationManager!, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
            break
        case .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
            break
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
            break
        case .restricted:
            // restricted by e.g. parental controls. User can't enable Location Services
            break
        case .denied:
            // user denied your app access to Location Services, but can grant access from Settings.app
            break
        default:
            break
        }
    }
}

class MainViewController: UIViewController, WKNavigationDelegate{

    //Instance of ItemsViewController
    let ivc = ItemsViewController(nibName: nil, bundle: nil)

    //used to cache already ranged unkown iBeacons -> avoid backend overloading
    var alreadyRangedItems = [Item]()
    
    //TIME
    var startDate = Date()
    var toastStartDate = Date()
    
    //CORE DATA
    let appDelegate = UIApplication.shared.delegate as! AppDelegate //delegate of AppDelegate
    
    //CORE LOCATION
    //Entry point into core location
    let locationManager = CLLocationManager()
    //current location coordinates
    var currentLocation = Coordinate(latitude: 0, longitude: 0)
    
    //LOCAL NOTIFICATIONS PUBLISHER
    private let notificationPublisher = NotificationPublisher()
    
    //FIREBASE REALTIME DATABASE
    var ref: DatabaseReference!
    
    //PAIRING FLAG
    var searchIsOn = false
    var pairingIsOn = false
    
    //UI Connections
    @IBOutlet weak var search: UIButton!
    @IBOutlet weak var mainPage: WKWebView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadMainPage()
        
        //CLBEACON REAGION
        //Allow beacon reagion to notify if the device entered or exited from it
        AppConstants.region.notifyEntryStateOnDisplay = true
        AppConstants.region.notifyOnEntry = true
        AppConstants.region.notifyOnExit = true
        
        //LOAD DATA
        ivc.loadItems()
        
//        print("LOADED")
//        for item in ivc.items {
//            printItem(item: item)
//        }
//
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: UIApplication.willResignActiveNotification, object: nil)
        
//        let userDefaults = UserDefaults.standard
//        let encodedData: Data = NSKeyedArchiver.archivedData(withRootObject: ivc.items)
//        userDefaults.set(encodedData, forKey: storedItemsKey)
//        userDefaults.synchronize()
//
//        ivc.items = [Item]()
//
//        print("DELETED")
//        for item in ivc.items {
//            printItem(item: item)
//        }
//
//        print()
        
        //CORE LOCATION
        setUpLocationManager()
        
        //FIREBASE REALTIME DATABASE REFERENCE
        ref = Database.database().reference()
        
        registerUser()
    
        sendNotification(titolo: "Titolo", mac: "CE83111B-908F-434D-B6EF-8849AB99BE92", beacon_id: "5A4BCFCE-174E-4BAC-A814-092E77F6B7E5_32_32", gps: "000_000", command: "CHECK_ALARM", regiID: "APA91bEeQpKqoHlK9aWR57A_J7q-StE87xOUwLMBCjXyEklqFOw5Q2MJ6EBjq-oVo8uff8KziQymiAfJ_4IGBA2W0-9d4VS2N8clgQGJozPNLRkIcYK-wds1OuEbpUQ3Qy0UFgoPrA9O", antenna_name: "Patrick", antenna_phone: "0000000000")
        
        //regiID: APA91bEEJKPJ4VODFC1dPski0pk3By9_xd0oet678MC90nfVQN_KvDK29MzSSdfoTTsRTgSLsmewgrlFtNxYnRf_oIaXlFRheoX21GqYnn-TjmM6s2Pj8HgRwIsDp9yvxjylh2TAQkFI_

    }
    
    @objc func appMovedToBackground() {
        print("ClickFineder is now in background")
        
        pairingIsOn = false
    
        start()
//        let userDefaults = UserDefaults.standard
//        let encodedData: Data = NSKeyedArchiver.archivedData(withRootObject: ivc.items)
//        userDefaults.set(encodedData, forKey: storedItemsKey)
//        userDefaults.synchronize()
    }
    
    /*********************************************
    UI ACTIONS & UI COMPONENTS
    **********************************************/
    
    @IBAction func searchIBeacon(_ sender: Any) {
        searchIsOn = true
        pairingIsOn = true
        
        start()
    }
    
    func loadMainPage(){
        mainPage.scrollView.contentInsetAdjustmentBehavior = UIScrollView.ContentInsetAdjustmentBehavior.never
        
        let url = AppConstants.mainPageURL!
        mainPage.load(URLRequest(url: url))
        mainPage.allowsBackForwardNavigationGestures = true
    }
    
    /*
     This function creates a new toast with the given message
     */
    func showToast(message : String) {
        let toastLabel = UILabel(frame: CGRect(x: self.view.frame.size.width/2 - 75, y: self.view.frame.size.height-100, width: 150, height: 60))
        self.view.bringSubviewToFront(toastLabel)
        toastLabel.numberOfLines = 2
        toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        toastLabel.textColor = UIColor.white
        toastLabel.textAlignment = .center;
        toastLabel.font = UIFont(name: "Montserrat-Light", size: 9.0)
        toastLabel.text = message
        toastLabel.alpha = 1.0
        toastLabel.layer.cornerRadius = 10;
        toastLabel.clipsToBounds  =  true
        self.view.addSubview(toastLabel)
        UIView.animate(withDuration: 2.0, delay: 3, options: .curveEaseOut, animations: {
            toastLabel.alpha = 0.0
        }, completion: {(isCompleted) in
            toastLabel.removeFromSuperview()
        })
    }
    
    /*
     Returns true if the app is in the foregroung, false if it is not.
     */
    func checkIfActive() -> Bool{
        switch UIApplication.shared.applicationState{
        case .background, .inactive :
            return false
        case .active :
            return true
        default:
            return false
        }
    }
    /*********************************************/
    
    //completion: @escaping(String)->() per estrarre il valore da una closure quando é pronto
    func getToken(completion: @escaping(String)->()) {
        InstanceID.instanceID().instanceID { (result, error) in
            var tokenID: String = ""
            if let error = error {
                print("Error fetching remote instance ID: \(error)")
                
            } else if let result = result {
                print("Remote instance ID token: \(result.token)")
                tokenID = result.token
            }
            completion(tokenID);
        }
    }
    
    func registerUser(){
        let iphoneID = UIDevice.current.identifierForVendor?.uuidString
        
        getToken { (token: String) in
            let tokenID: String = token
            let tipoSchermo: String = "iOS_LAC_regId_"+tokenID
            print("TOKEN", tokenID)
            print("IPHONE ID",iphoneID!)
            
            self.ref.child("users").child(iphoneID!).setValue(["tiposchermo":tipoSchermo, "switch_hdd": "0", "mac": iphoneID!]) {
                (error:Error?, ref:DatabaseReference) in
                if let error = error {
                    print("Data could not be saved: \(error).")
                } else {
                    print("Data saved successfully!")
                }
            }
        }
    }
    
    /*********************************************
     IBEACON MANAGING
     *********************************************/
    
    /*
     Cycles the users table and checks if the passed beacon has been lost by someone.
     If the passed item is owned by the user, it swtich_hdd value is reset.
     Else, the app notificates the main server that a lost item has been found in the current location.
     */
    func checkIfLost(item: Item, known: Bool){
        let beaconID = "\(item.uuid.uuidString)_\(Int(item.majorValue))_\(Int(item.minorValue))"
        
        let iBeaconsRef = self.ref.child("users")
        
        iBeaconsRef.observe(.value, with: { (snapshot) in
            for child in snapshot.children {
                if let childSnapshot = child as? DataSnapshot{
                    let value = childSnapshot.value as? NSDictionary
                    let mac = value?["mac"] as? String ?? ""
                    let switch_hdd = value?["switch_hdd"] as? String ?? ""
                    
                    if mac == beaconID && switch_hdd == "1" && !known{
                        //Unknown lost iBeacon found, notify the server with current location
                        print("Current location: lat=\(self.currentLocation.latitude), long=\(self.currentLocation.longitude)")
                        print("set current beacon location")
                        print("send notification")
                    } else if mac == beaconID && switch_hdd == "1" && known{
                        //Known lost iBeacon found while app was in background
                        //Request the server to send a notification so that the user is aware of
                        if !self.checkIfActive(){
                            print("Server has to notify me that i've found my lost keys")
                            self.locationManager.stopRangingBeacons(in: AppConstants.region)
                            self.updateBeaconStatus(beaconID: beaconID, lost: false)
                        }else{
                            print("Found known \(beaconID), set switch_hdd to 0")
                            self.locationManager.stopRangingBeacons(in: AppConstants.region)
                            self.updateBeaconStatus(beaconID: beaconID, lost: false)
                        }
                    }
                }
            }
        })
    }
    
    /*
     This function updates the iBeacon status on the database.
     Usually this function is called when a lost known iBeacon has been found or when a know beacon cant' be found.
     */
    func updateBeaconStatus(beaconID: String, lost: Bool){
        
        var values = [String:String]()
        
        if lost{
            values = ["switch_hdd": "1"]
        }else{
            values = ["switch_hdd": "0"]
        }
        
        self.ref.child("users").child(beaconID).updateChildValues(values)
    }
    
    /*******************************************/
    
    /*******************************************
     FIREBASE
     *******************************************/
    
    func sendNotification(titolo: String, mac: String, beacon_id: String, gps: String, command: String, regiID: String, antenna_name: String, antenna_phone: String) {
        print("Notifica inviata")
        let urlString: String = "https://fcm.googleapis.com/fcm/send"
        let time_to_live = 3600
        
        let notification: [String: Any] = [
            "title": titolo,
            "body": mac,
            //"url": urlString,
            "command": command,//"CHECK_ALARM"
            "param": beacon_id,
            "value": gps, //GPS latitude + "_" + longitude
            "from": regiID, //token destinatario
            "antenna_name": antenna_name,
            "antenna_phone": antenna_phone
        ]
        
        
        let message: [String: Any] = [
            "priority": "high",
            "content_available": true,
            "time_to_live": time_to_live,
            //"collapse_key": min,
            
            "to": regiID,
            "notification": notification
            //"title":"Beacon trovato",
            //"body":"ivan ha trovato il tuo beacon"
        ]
        
        
        let header: HTTPHeaders = [ "Content-Type": "application/json",
                                    "Accept": "application/json",
                                    "Authorization": "key=AIzaSyCu-EtxJSmRGA2ll2W66ugs5Rfy1oa3vZs"
        ]
        
        AF.request(urlString, method: .post, parameters: message, encoding: JSONEncoding.default, headers: header).responseString {
            response in
            switch response.result {
            case .success:
                print("SUCCESS: ", response)
                
                break
            case .failure(let error):
                print("FAILURE: ", error)
            }
        }
        
    }
}

//Allerts
extension MainViewController{
    func createAlert(title: String, message: String, item: Item){
        
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        //Annulla il pairing
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) in
            
            alertController.dismiss(animated: true, completion: nil)
        }))
        
        //TODO aprire la pagina di registrazione con i campi inerenti il beacon già compilati
        alertController.addAction(UIAlertAction(title: "Pair", style: .default, handler: { (action) in
            self.ivc.addItemToBeAdded(item: item)
            //self.ivc.addBeacon(item: item)
        }))
        
        self.present(alertController, animated: true, completion: nil)
    }
}
