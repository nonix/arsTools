// 01. Input: tape_name, collection_name
// 10. get filesystem(tape_name).size => tape_size
// 20. calculate N number of chunks as: int(tape_size / 64421888) + 1
// 30. allocate 32k buffer
// 40. open ifstream(tape_name)
// 50. loop for offset=0;offset<tape_size;offset += 64421888
// 52.  ifstream.seek(offset)
// 55. 	loop
// 60. 		bytes_read=ifsteam.read(buffer)
// 70. 		search in buffer for (collection name)
// 75.		if found => offset +=found_at, end loop@55
// 76.		  else offset += bytes_read
// 80.  start thread "slicer" with input: tape_name, offset
// 90. 	  the slicer:
// 100.		open ifstream(tape_name)
// 105.		allocate 32k buffer
// 110.		ifstream.seek(offset)
// 115.		loop while ifstream.tell < offset+64421888
// 120.			bytes_read=ifstream.read(buffer,32k) 
// 125.			parse 128 bytes of header (see appendix: a), error if header.filename has non-printable chars
// 130.			ofstream.open(header.filename, mode:binary,append)
// 140.			if header.size.decode+128 < bytes_read => report Error
// 150.			ofstream.write(buffer.decode,from_128,length of header.size.decode) # decode: see appendix b.
// 155.			ofstream.close
// 160.			ifstream.seek(CUR_POS,header.size.decode+128-bytes_read) # seek backwards unless the size was of 32k (aka full buffer)
// 170.			ifstream.eof end loop@115
// 180.		delete buffer; ifstream.close
// appendix a.
/* 
	typedef struct {
			char collection[44];		// do not decode, in ASCII, left space padding
			char filename[44];			// do not decode, in ASCII, left space padding
			union {
				uint32_t filesize;		// after decode, big endian, represents total file size
				uint8_t filesize_b[4];	
			};
			uint32_t _unknown;			// seems like zero padding
			union {
				uint32_t segsize;		// after decode, big endian, represents this segment size
				uint8_t segsize_b[4];
			};
			uint8_t oam_tag[28]; 		// *OAM zero padded
			} header_t;
*/
// appendix b.
/* 
	const uint8_t map[] = {
		0x00,0x01,0x02,0x03,0x37,0x2D,0x2E,0x2F,0x16,0x05,0x15,0x0B,0x0C,0x0D,0x0E,0x0F,
		0x10,0x11,0x12,0x13,0x3C,0x3D,0x32,0x26,0x18,0x19,0x3F,0x27,0x1C,0x1D,0x1E,0x1F,
		0x40,0x5A,0x7F,0x7B,0x5B,0x6C,0x50,0x7D,0x4D,0x5D,0x5C,0x4E,0x6B,0x60,0x4B,0x61,
		0xF0,0xF1,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF8,0xF9,0x7A,0x5E,0x4C,0x7E,0x6E,0x6F,
		0x7C,0xC1,0xC2,0xC3,0xC4,0xC5,0xC6,0xC7,0xC8,0xC9,0xD1,0xD2,0xD3,0xD4,0xD5,0xD6,
		0xD7,0xD8,0xD9,0xE2,0xE3,0xE4,0xE5,0xE6,0xE7,0xE8,0xE9,0xAD,0xE0,0xBD,0x5F,0x6D,
		0x79,0x81,0x82,0x83,0x84,0x85,0x86,0x87,0x88,0x89,0x91,0x92,0x93,0x94,0x95,0x96,
		0x97,0x98,0x99,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7,0xA8,0xA9,0xC0,0x4F,0xD0,0xA1,0x07,
		0x20,0x21,0x22,0x23,0x24,0x25,0x06,0x17,0x28,0x29,0x2A,0x2B,0x2C,0x09,0x0A,0x1B,
		0x30,0x31,0x1A,0x33,0x34,0x35,0x36,0x08,0x38,0x39,0x3A,0x3B,0x04,0x14,0x3E,0xFF,
		0x41,0xAA,0x4A,0xB1,0x9F,0xB2,0x6A,0xB5,0xBB,0xB4,0x9A,0x8A,0xB0,0xCA,0xAF,0xBC,
		0x90,0x8F,0xEA,0xFA,0xBE,0xA0,0xB6,0xB3,0x9D,0xDA,0x9B,0x8B,0xB7,0xB8,0xB9,0xAB,
		0x64,0x65,0x62,0x66,0x63,0x67,0x9E,0x68,0x74,0x71,0x72,0x73,0x78,0x75,0x76,0x77,
		0xAC,0x69,0xED,0xEE,0xEB,0xEF,0xEC,0xBF,0x80,0xFD,0xFE,0xFB,0xFC,0xBA,0xAE,0x59,
		0x44,0x45,0x42,0x46,0x43,0x47,0x9C,0x48,0x54,0x51,0x52,0x53,0x58,0x55,0x56,0x57,
		0x8C,0x49,0xCD,0xCE,0xCB,0xCF,0xCC,0xE1,0x70,0xDD,0xDE,0xDB,0xDC,0x8D,0x8E,0xDF
	};
*/
// appendix c.
//	base64 with Unix EOL encoded binary data sample of a tape:
/*
Yj59wX0WM0nir7W5wFnZghA0nwHhBmmbWklBNkEuQ09MLkFHUU1BQS5BMDAxICAg
ICAgICAgICAgICAgICAgICAgICBGR0kuTDQ0Ny5GQUExICAgICAgICAgICAgICAg
ICAgICAgICAgICAgICAgICAgAfQgICAgICAB9CpPQU0gICAgICAgICAgICAgICAg
ICAgICAgICDs5qdtKT50kBDYpMV8agt1kp/7S6aFj+dZjhKmgHZgSdk/SvHuXEs1
3muiuId7CNqe9fDZE6p0Bwd2H4rHrRLiyWjwASex0lbo4R8DDMndRKZHlGSmaD0H
EMa72cuNuLFD95dHS88p5P/XPZC/dSD+HBlzYpE0fnn1mCjrknUivKO5PwXL/Jks
AaQwCH06j3WuqjsEzSmHHj5DDBTn0c76TCCIwxkVGKZYLWSDXSTIqUh0JWFPoiac
cTEoBFT75I/hhiJji4H8g4ZYIo+YTakrFqx4RbWbvORG2H5Tl0vs2c0JVT700Pv2
ao4wOisZlzqtMW6AxUVF5OHsM3JtswM9t6Kgly4P6OTpwZ2Yii8gIa1DcAolpIgH
dzS/nmjyR0nQYhKyoYBOKY5oYjI2xa6JC7rNIHjsnc56EGwPGQmg1Pim58teg8AK
VXGIGz953Z0iH+OqDM0rYbItWpgqYDeI54tt2XWQ8r6WfpddvYpIUi3XqusZA2lm
Nq6dqK4KHEVr0mD4M74OLh80By4f8PpyHF7Lmmii/GCFFUgit3oCJ01S2+csA60Z
MR1AWxPXyz+ZtEoS11+ftjsyn7P7HBZAKHjY2WefDtqQKzRaSUE2QS5DT0wuQUdR
TUFBLkEwMDEgICAgICAgICAgICAgICAgICAgICAgIEZHSS5MNDQ4LkZBQUEgICAg
ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAcAiAgICAgIBwCKk9BTSAgICAg
ICAgICAgICAgICAgICAgICAgIMwB0rjx7/uttkfXqldP2ZfPBSxACLTLTzpJFrZT
IA==
 */
#include <iostream>
#include <fstream>
#include <vector>
#include <cstring>  // For memcmp

const size_t BUFFER_SIZE = 32 * 1024; // 32KB buffer size

// Function to search for a pattern in a buffer and return the index in byte offset
long long searchPattern(const std::vector<char>& buffer, const std::vector<char>& pattern, long long offset) {
    for (size_t i = 0; i <= buffer.size() - pattern.size(); ++i) {
        if (std::memcmp(&buffer[i], pattern.data(), pattern.size()) == 0) {
            return offset + i; // Return byte offset of pattern found
        }
    }
    return -1; // Pattern not found
}

int main(int argc,char *argv[]) {
    // Open the binary file
    std::ifstream file(argv[1], std::ios::binary);
    if (!file) {
        std::cerr << "Failed to open file." << std::endl;
        return 1;
    }

    // Allocate a buffer of 32KB
    std::vector<char> buffer(BUFFER_SIZE);

    // Define the pattern to search for (example: "ABCD")
	std::vector<char> pattern;
	pattern.assign(argv[2],argv[2]+strlen(argv[2]));

    long long fileOffset = 0;  // To track the byte offset in the file

    // Read the file in chunks of 32KB
    while (file.read(buffer.data(), BUFFER_SIZE) || file.gcount() > 0) {
        // Search for the pattern in the buffer
        long long offset = searchPattern(buffer, pattern, fileOffset);
        if (offset != -1) {
            std::cout << "Pattern found at byte offset: " << offset << std::endl;
        }

        // Update the file offset by the number of bytes read
        fileOffset += file.gcount();
        
        // Optionally handle the last partial chunk if needed
        if (file.gcount() < BUFFER_SIZE) {
            std::vector<char> partialBuffer(file.gcount());
            file.read(partialBuffer.data(), file.gcount());
            offset = searchPattern(partialBuffer, pattern, fileOffset);
            if (offset != -1) {
                std::cout << "Pattern found in the last partial chunk at byte offset: " << offset << std::endl;
                break;
            }
        }
    }

    // Close the file
    file.close();

    return 0;
}
