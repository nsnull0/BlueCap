//
//  PeripheralViewController.swift
//  BlueCap
//
//  Created by Troy Stribling on 6/16/14.
//  Copyright (c) 2014 Troy Stribling. The MIT License (MIT).
//

import UIKit
import CoreBluetooth
import BlueCapKit


class PeripheralViewController : UITableViewController {

    fileprivate static var BCPeripheralStateKVOContext = UInt8()

    weak var peripheral: Peripheral!
    weak var connectionFuture: FutureStream<(peripheral: Peripheral, connectionEvent: ConnectionEvent)>!

    var peripheralConnected = true
    var peripheralDiscovered = false

    let dateFormatter = DateFormatter()

    @IBOutlet var uuidLabel: UILabel!
    @IBOutlet var rssiLabel: UILabel!
    @IBOutlet var stateLabel: UILabel!
    @IBOutlet var serviceLabel: UILabel!
    @IBOutlet var serviceCount: UILabel!
    @IBOutlet var serviceDiscoverySpinner: UIActivityIndicatorView!

    @IBOutlet var discoveredAtLabel: UILabel!
    @IBOutlet var connectedAtLabel: UILabel!
    @IBOutlet var connectionsLabel: UILabel!
    @IBOutlet var disconnectionsLabel: UILabel!
    @IBOutlet var timeoutsLabel: UILabel!
    @IBOutlet var secondsConnectedLabel: UILabel!
    @IBOutlet var avgSecondsConnected: UILabel!
    
    struct MainStoryBoard {
        static let peripheralServicesSegue  = "PeripheralServices"
        static let peripehralAdvertisementsSegue = "PeripheralAdvertisements"
    }
    
    required init?(coder aDecoder:NSCoder) {
        super.init(coder:aDecoder)
        self.dateFormatter.dateStyle = .short
        self.dateFormatter.timeStyle = .short
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.title = self.peripheral.name
        self.discoveredAtLabel.text = dateFormatter.stringFromDate(self.peripheral.discoveredAt)
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title:"", style:.plain, target:nil, action:nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.setConnectionStateLabel()
        self.peripheralConnected = (self.peripheral.state == .Connected)
        self.discoverPeripheral()
        self.setConnectionStateLabel()
        self.toggleRSSIUpdates()
        self.updatePeripheralProperties()
        let options = NSKeyValueObservingOptions([.new])
        // TODO: Use Future Callback
        self.peripheral.addObserver(self, forKeyPath: "state", options: options, context: &PeripheralViewController.BCPeripheralStateKVOContext)
        NotificationCenter.default.addObserver(self, selector: #selector(PeripheralViewController.willResignActive), name: NSNotification.Name.UIApplicationWillResignActive, object :nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.peripheral.stopPollingRSSI()
        super.viewDidDisappear(animated)
        self.peripheral.removeObserver(self, forKeyPath: "state", context: &PeripheralViewController.BCPeripheralStateKVOContext)
        NotificationCenter.default.removeObserver(self)
    }
    
    override func prepare(for segue:UIStoryboardSegue, sender:Any!) {
        if segue.identifier == MainStoryBoard.peripheralServicesSegue {
            let viewController = segue.destination as! PeripheralServicesViewController
            viewController.peripheral = self.peripheral
            viewController.peripheralViewController = self
        } else if segue.identifier == MainStoryBoard.peripehralAdvertisementsSegue {
            let viewController = segue.destination as! PeripheralAdvertisementsViewController
            viewController.peripheral = self.peripheral
        }
    }
    
    override func shouldPerformSegue(withIdentifier identifier: String?, sender: Any?) -> Bool {
        if let identifier = identifier {
            if identifier == MainStoryBoard.peripheralServicesSegue {
                return self.peripheralDiscovered
            } else {
                return true
            }
        } else {
            return true
        }
    }

    func willResignActive() {
        self.navigationController?.popToRootViewController(animated: false)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath != nil else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        switch (keyPath!, context) {
        case("state", PeripheralViewController.BCPeripheralStateKVOContext):
            if let change = change, let newValue = change[NSKeyValueChangeKey.newKey], let newRawState = newValue as? Int, let newState = CBPeripheralState(rawValue: newRawState) {
                DispatchQueue.main.async {
                    self.peripheralConnected = (newState == .connected)
                    self.setConnectionStateLabel()
                    self.toggleRSSIUpdates()
                    self.discoverPeripheral()
                    self.updatePeripheralProperties()
                }
            }
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func updatePeripheralProperties() {
        if let connectedAt = self.peripheral.connectedAt {
            self.connectedAtLabel.text = dateFormatter.stringFromDate(connectedAt)
        }
        self.rssiLabel.text = "\(self.peripheral.RSSI)"
        self.connectionsLabel.text = "\(self.peripheral.connectionCount)"
        self.secondsConnectedLabel.text = "\(Int(self.peripheral.cumlativeSecondsConnected))"
        if self.peripheral.connectionCount > 0 {
            self.avgSecondsConnected.text = "\(Int(self.peripheral.cumlativeSecondsConnected) / self.peripheral.connectionCount)"
        } else {
            self.avgSecondsConnected.text = "0"
        }
        self.disconnectionsLabel.text = "\(self.peripheral.disconnectionCount)"
        self.timeoutsLabel.text = "\(self.peripheral.timeoutCount)"
    }

    func toggleRSSIUpdates() {
        if self.peripheralConnected {
            let rssiFuture = self.peripheral.startPollingRSSI(Params.peripheralViewRSSIPollingInterval, capacity: Params.peripheralRSSIFutureCapacity)
            rssiFuture.onSuccess { [unowned self] _ in
                self.updatePeripheralProperties()
            }
        } else {
            self.peripheral.stopPollingRSSI()
        }

    }

    func discoverPeripheral() {
        guard self.peripheralConnected && !self.peripheralDiscovered else {
            return
        }
        let peripheralDiscoveryFuture = self.peripheral.discoverAllPeripheralServices()
        self.toggleDiscoveryIndicator()
        peripheralDiscoveryFuture.onSuccess { _ in
            self.peripheralDiscovered = true
            self.setConnectionStateLabel()
        }
        peripheralDiscoveryFuture.onFailure { error in
            if error.code != BCError.peripheralServiceDiscoveryInProgress.code {
                self.serviceLabel.textColor = UIColor.lightGrayColor()
                self.presentViewController(UIAlertController.alertOnError("Peripheral Discovery Error", error: error, handler: { action in
                    self.setConnectionStateLabel()
                }), animated: true, completion:nil)
            }
        }
    }

    func toggleDiscoveryIndicator() {
        if self.peripheralDiscovered {
            self.serviceLabel.textColor = UIColor.black
            self.serviceCount.isHidden = false
            self.serviceDiscoverySpinner.stopAnimating()
        } else {
            self.serviceLabel.textColor = UIColor.lightGray
            self.serviceCount.isHidden = true
            self.serviceDiscoverySpinner.startAnimating()
        }
    }

    func setConnectionStateLabel() {
        if self.peripheralConnected {
            self.stateLabel.text = "Connected"
            self.stateLabel.textColor = UIColor(red: 0.1, green: 0.7, blue: 0.1, alpha: 1.0)
        } else {
            self.stateLabel.text = "Disconnected"
            self.stateLabel.textColor = UIColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1.0)
        }
        self.toggleDiscoveryIndicator()
        self.serviceCount.text = "\(self.peripheral.services.count)"
    }
    
}
