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


if __name__ == '__main__':
    # Connect to the teensy
    print("Connecting to device..")
    serial_device = connect_to_teensy('COM9')

    time.sleep(0.1)       # allow connection to be established
    if serial_device.in_waiting:
        serial_device.reset_input_buffer()

    blockNumber = 1
    amount = 5          # how many messages to send
    countt = 0          # count of messages suffessfully sent
    ackCount = 0        # count successful sends
    badAckCount = 0     # how many messages had negative ack

    serial_device.write(ENQ.to_bytes(1, 'little'))

    while not serial_device.in_waiting:
        continue

    if int.from_bytes(serial_device.read(1), 'little') == NAK:
        print("Got handshake - begin transfer")
    else:
        print("Invalid handshake, exiting..")
        exit()

    tIn = time.time()

    for y in range(10):
        # Block: SOH, Block Number, 128 bytes of data, chksum
        print("Sending block {}..".format(blockNumber), end ="")
        serial_device.write(SOH.to_bytes(1, 'little'))
        serial_device.write(blockNumber.to_bytes(1, 'little'))
        for x in range(128):
            data = 0
            serial_device.write(data.to_bytes(1, 'little'))
            time.sleep(0.001)   # Prevent overloading Teensy buffers
        chksum = 0
        serial_device.write(chksum.to_bytes(1, 'little'))

        while not serial_device.in_waiting:
            continue

        reply = int.from_bytes(serial_device.read(1), 'little')

        if reply == ACK:
            print(" OK!".format(blockNumber))
            blockNumber += 1
        else:
            print("error - resending block {}".format(reply, blockNumber))

    serial_device.write(EOT.to_bytes(1, 'little'))
    tOut = time.time()
    txTime = tOut-tIn
    size = (blockNumber-1)*131  # Total amount of sent bytes
    speed = size/txTime
    print("Transfer complete in {:.2f}s".format(txTime))
    print("Sent {:.0f} bytes @ {:.2f} bytes per second".format(size, speed))

    while serial_device.in_waiting:
        print(serial_device.read())
    exit()

    # Printing the speeds
    # print(tOut - tIn)
    # print 'Average time for one communication: (%f) seconds.' % (1.0 * (tOut - tIn) / amount)
    # print 'Sent = (%d), Received = (%d)' % (amount, countt)
    # print Wrong AckNum = (%d), Not Equals = (%d)' % (wrongAck, noEquals)
