//
//  ViewController.swift
//  CCLoaderX
//
//  Created by Alex on 08/10/2017.
//  Copyright © 2017 Hangar42. All rights reserved.
//
//  The Erase button is hidded because the CCLoader sketch triggers a complete reset of
//  the flash memory at the beginning of the cycle, so doing it manually should not be
//  necessary.
//

import Cocoa

class ViewController: NSViewController, NSComboBoxDataSource, ORSSerialPortDelegate, DropZoneDelegate {
    
    @IBOutlet weak var portComboBox: NSComboBox!
    @IBOutlet weak var filePathField: NSTextField!
    @IBOutlet var logTextView: NSTextView!
    
    var manager = ORSSerialPortManager.shared()
    var serial: ORSSerialPort!
    
    var url: URL!
    var data: Data!
    var blkTot = 0
    var blkNum = 0

    var logTextStorage = ""
    var isFlashing = false
    var erase = false
    
    let codes = (begin: UInt8(0x01),
                  data: UInt8(0x02),
              response: UInt8(0x03),
                   end: UInt8(0x04),
                 error: UInt8(0x05))
    
    let eraseBlkTot = 512
    
    
    // MARK: - NSViewController

    override func viewDidLoad() {
        super.viewDidLoad()
        portComboBox.reloadData()
        
        (view as! DropZoneView).dropDelegate = self
        (view as! DropZoneView).registerForFileExtensions(["bin"])
    }
    
    private func log(_ string: String) {
        logTextView.string.append(string)
        let length = logTextView.string.characters.count
        let range: NSRange = NSMakeRange(length, 0)
        logTextView.scrollRangeToVisible(range)
    }
    
    private func delay(_ delay: Double, callback: @escaping ()->()) {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + delay, execute: callback)
    }
    
    
    // MARK: - Uploading Sequence
    
    private func start() {
        openSerial()
    }
    
    private func openSerial() {
        log("Opening serial port... ")
        serial = ORSSerialPort(path: portComboBox.stringValue)
        
        if serial == nil {
            log("Failed!\n")
            return
        }
            
        serial.baudRate = NSNumber(value: 115200)
        serial.delegate = self
        serial.parity = .none
        serial.numberOfStopBits = 1
        serial.dtr = false
        serial.rts = false
        serial.open()
    }
    
    private func openFile() {
        if erase {
            blkTot = eraseBlkTot
            data = Data(repeating: UInt8(0xFF), count: blkTot*512)
            log("Waiting for Arduino setup... ")
            delay(5, callback: enableTransmission)
            return
        }
        
        do {
            log("Success!\n")
            log("Opening file... ")
            
            url = URL(string: "file://" + filePathField.stringValue)
            
            if url == nil {
                log("Failed - Invalid URL\n")
                serial.close()
                return
            }
            
            data = try Data(contentsOf: url!)
            log("Success!\n")
            
            if data.count % 512 != 0 {
                log("Warning: file size isn't the integer multiples of 512, last bytes will miss to be sent!\n")
            }
            
            blkTot = Int(floor(Double(data.count)/512.0))
            log("Size: \(data.count) bytes, Blocks: \(blkTot)\n")
            
            log("Waiting for Arduino setup... ")
            delay(5, callback: enableTransmission)
        } catch {
            log("\nFailed: \(error.localizedDescription)\n")
            serial.close()
            return
        }
    }
    
    private func enableTransmission() {
        log("Done!\n")
        log("Enable transmission... ")
        if serial.send(Data(bytes: [codes.begin, 0x00])) == false {
            log("Failed!")
            serial.close()
        } else {
            log("Success!\nWaiting for response... ")
            delay(5) {
                guard !self.isFlashing && self.serial != nil && self.serial.isOpen else { return }
                self.log("Timed out.\n")
                self.serial.close()
            }
        }
    }
    
    private func handle(_ received: Data) {
        for byte in received {
            switch byte {
            case codes.response:
                if blkNum == blkTot {
                    log("\nDone programming\n")
                    serial.send(Data(bytes: [codes.end]))
                    delay(2) {
                        self.serial.close()
                    }
                } else {
                    if blkNum == 0 {
                        log("Done!\n")
                        log("Beginning programming\n")
                        log("Sending block ")
                        
                        // save this state of the log
                        logTextStorage = logTextView.string
                    }
                    
                    isFlashing = true
                    
                    let pos = blkNum * 512
                    let blk = data[pos ... pos+511]
                    var buffer = Data(count: 515)
                    buffer[0] = codes.data
                    buffer[1 ... 512] = blk
                    
                    var checksum: UInt16 = 0x0000
                    blk.forEach {
                        checksum = checksum.addingReportingOverflow(UInt16($0)).partialValue
                    }
                    buffer[513] = UInt8((checksum >> 8) & 0x00FF)
                    buffer[514] = UInt8(checksum & 0x00FF)
                    
                    serial.send(buffer)
                    
                    logTextView.string = logTextStorage
                    
                    blkNum += 1
                    log("\(blkNum) of \(blkTot)")
                }
                
            case codes.error:
                if isFlashing {
                    log("\nVerify failed!\n")
                    serial.close()
                } else {
                    log("No chip detected!\n")
                    serial.close()
                }
            default:
                log("Unknown response received: \(byte)")
            }
        }
    }
    

    // MARK: - ORSSerialPortDelegate functions
    
    func serialPortWasRemoved(fromSystem givenSerialPort: ORSSerialPort!) {
        guard givenSerialPort == serial else { return }
        log("Serial port was removed\n")
        serial = nil
        url = nil
        data = nil
        blkNum = 0
        blkTot = 0
        erase = false
        isFlashing = false
        
        // display an alert
        let alert = NSAlert()
        alert.messageText = "The device has been disconnected!"
        alert.addButton(withTitle: "Dismiss")
        alert.alertStyle = NSAlert.Style.informational
        alert.runModal()
    }
    
    func serialPortWasOpened(_ givenSerialPort: ORSSerialPort!) {
        openFile()
    }
    
    func serialPortWasClosed(_ givenSerialPort: ORSSerialPort!) {
        log("Serial port closed\n")
        serial = nil
        url = nil
        data = nil
        blkNum = 0
        blkTot = 0
        erase = false
        isFlashing = false
    }
    
    func serialPort(_ serialPort: ORSSerialPort!, didEncounterError error: Error!) {
        log("\nSerial port \(serialPort.path) has encoutered an error:\n\(error.localizedDescription)\n")
    }
    
    func serialPort(_ givenSerialPort: ORSSerialPort!, didReceive data: Data!) {
        handle(data)
    }
    
    
    // MARK: - DropZoneView
    
    func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        if let urls = DropZoneView.fileUrlsFromDraggingInfo(info),
              let first = urls.first {
            filePathField.stringValue = first.path
            return true
        }
        
        return false
    }

    
    // MARK: - NSCombobox
    
    func comboBox(_ aComboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
        let port = manager!.availablePorts[index] as! ORSSerialPort
        return port.path
    }
    
    func numberOfItems(in aComboBox: NSComboBox) -> Int {
        return manager!.availablePorts.count
    }
    
    
    // MARK: - IBActions
    
    @IBAction func reloadPorts(_ sender: NSButton) {
        portComboBox.reloadData()
    }
    
    @IBAction func openFileDialog(_ sender: NSButton) {
        let dialog = NSOpenPanel();
        dialog.title                   = "Choose a .bin file";
        dialog.showsResizeIndicator    = true;
        dialog.showsHiddenFiles        = false;
        dialog.canChooseDirectories    = false;
        dialog.canCreateDirectories    = false;
        dialog.allowsMultipleSelection = false;
        dialog.allowedFileTypes        = ["bin"];
        
        if (dialog.runModal() == NSApplication.ModalResponse.OK) {
            let result = dialog.url
            if (result != nil) {
                let path = result!.path
                filePathField.stringValue = path
            }
        }
    }
    
    @IBAction func upload(_ sender: NSButton) {
        erase = false
        start()
    }
    
    @IBAction func erase(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Erase all flash memory?"
        alert.informativeText = "This will upload 256KB (512 blocks) of 0xFF bytes to the chip and erases all existing data."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            erase = true
            start()
        }
    }
    
    @IBAction func clearConsole(_ sender: Any) {
        logTextView.string = ""
    }
    
    @IBAction func showHelp(_ sender: Any) {
        let url = URL(string: "http://www.hangar42.nl/ccloader")!
        NSWorkspace.shared.open(url)
    }
}

class AboutViewController: NSViewController {
    @IBAction func showHelp(_ sender: Any) {
        let url = URL(string: "http://www.hangar42.nl/ccloader")!
        NSWorkspace.shared.open(url)
    }
}
