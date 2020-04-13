import serial  # https://pythonhosted.org/pyserial/'
import serial.tools.list_ports  # https://pythonhosted.org/pyserial/
import time
# import numpy
import hashlib
import random
from time import sleep

SOH = 1 		# Start of heading
ENQ = 5			# Enquiry
ACK = 6 		# Acknowledge
NAK = 21 		# Negative acknowledge
EOT = 26 		# End of transfer


def connect_to_teensy(port):
    '''
    Connect to teensy and return serial object for read/write/query.
    '''

    settings = {}
    settings['port'] = port
    settings['timeout'] = None
    settings['writeTimeout'] = .1
    settings['baudrate'] = 1000000
    settings['parity'] = serial.PARITY_NONE
    serial_device = serial.Serial(**settings)

    return serial_device


def get_packages(file="a.out", with_checksum=True):
    '''
    Read binary file to 128 byte payload chunks to send forward, with or without trailing checksum
    '''
    temp_packages = []
    curr_package = []
    byte_count = 0
    with open(file, "rb") as f:
        byte = f.read(1)
        while byte:
            curr_package.append(byte)
            byte_count += 1
            if byte_count >= 128:
                temp_packages.append(curr_package)
                curr_package = []
                byte_count = 0
            byte = f.read(1)

    if byte_count > 0:  # Pad the remainder of the last package with zero bytes
        while byte_count < 128:
            curr_package.append(b'\x00')
            byte_count += 1
        temp_packages.append(curr_package)

    if with_checksum:
        for package in range(len(temp_packages)):
            chksum = 0
            for byte in temp_packages[package]:
                chksum += int.from_bytes(byte, "little")
            chksum %= 256
            temp_packages[package].append(chksum.to_bytes(1, 'little'))

    return temp_packages


if __name__ == '__main__':
    print("JMODEM binary transfer application v0.1")
    packages = get_packages(file="../65c02 RAM apps/Hello World/hello.bin", with_checksum=True)
    payloadSize = len(packages)*128
    transferSize = len(packages)*131
    ramUtilization = payloadSize/28159
    print("Parsed a {} byte payload, using {:.2f}% of available RAM".format(payloadSize, ramUtilization*100))

    if ramUtilization > 1:
        print("ERR: Package too large for target, exiting..")
        exit()

    # Connect to the target
    print("Connecting to device..")
    serial_device = connect_to_teensy('COM9')

    time.sleep(0.1)       # allow connection to be established
    serial_device.reset_input_buffer()

    # Send ENQ to start transaction, wait for reply
    serial_device.write(ENQ.to_bytes(1, 'little'))
    while not serial_device.in_waiting:
        continue

    if int.from_bytes(serial_device.read(1), 'little') == NAK:
        print("Got handshake - begin transfer")
    else:
        print("Invalid handshake, exiting..")
        exit()

    tIn = time.time()
    currBlock = 1
    while currBlock <= len(packages):
        # Block: SOH, Block Number, 128 bytes of data, chksum
        print("Sending block {}..".format(currBlock), end ="")
        serial_device.write(SOH.to_bytes(1, 'little'))
        serial_device.write(currBlock.to_bytes(1, 'little'))
        for byte in range(129):    # 128 byte payload + pre-calculated checksum
            serial_device.write(packages[currBlock-1][byte])
            time.sleep(0.001)   # Prevent overloading Teensy buffers

        # Get reply ack or nak, based on checksum validation result
        while not serial_device.in_waiting:
            continue
        reply = int.from_bytes(serial_device.read(1), 'little')

        if reply == ACK:
            print(" OK!".format(currBlock))
            currBlock += 1
        elif reply == NAK:
            print(" checksum err - resending block {}".format(reply, currBlock))
        else:
            print("Unknown reply {}, exiting..".format(reply))
            serial_device.write(EOT.to_bytes(1, 'little'))
            exit()

    serial_device.write(EOT.to_bytes(1, 'little'))
    txTime = time.time()-tIn
    speed = transferSize/txTime
    print("Transfer complete in {:.2f}s".format(txTime))
    print("Sent {:.0f} bytes @ {:.2f} bytes per second".format(transferSize, speed))

    serial_device.flush()
    exit()
