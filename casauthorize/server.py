#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class SimpleRESTHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        # Only respond to the /authorize endpoint
        if self.path == '/authorize':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')
            
            try:
                # Parse the JSON request
                data = json.loads(post_data)
                userid = data.get("userid", "")
                kontonr = data.get("kontonr", "0")
                
                print(f"\n--- Received Request ---")
                print(f"Raw JSON: {data}")
                
                # 1. Remove the "t" from userid and left pad with zero to 8 digits
                if userid.lower().startswith('t'):
                    userid_num_str = userid[1:]
                else:
                    userid_num_str = userid
                
                userid_num_str = userid_num_str.zfill(8)
                userid_int = int(userid_num_str)
                
                # DEBUG: Output after userid conversion
                print(f"[DEBUG] Step 1 - userid converted: '{userid}' -> stripped/padded: '{userid_num_str}' -> int: {userid_int}")
                
                # 2. Cast kontonr string to 8 bytes bigint (big-endian 64-bit integer)
                # Encode string to ASCII bytes, ensure it is exactly 8 bytes long
                
                kontonr_bytes = f"{kontonr:>8}".encode('ascii', errors='ignore')
                # Pad with null bytes if shorter than 8, truncate if longer
                # kontonr_bytes = (kontonr_bytes + b'\x00' * 8)[:8] 
                
                # Interpret the 8 bytes as a 64-bit big-endian integer
                kontonr_int = int.from_bytes(kontonr_bytes, byteorder='big', signed=False)
                
                # DEBUG: Output after kontonr byte-to-int conversion
                print(f"[DEBUG] Step 2 - kontonr converted: '{kontonr}' -> bytes hex: {kontonr_bytes.hex(' ')} -> int: {kontonr_int}")
                
                # 3. XOR the two numbers
                xor_result = userid_int ^ kontonr_int
                
                # DEBUG: Output XOR result
                print(f"[DEBUG] Step 3 - XOR result: {userid_int} ^ {kontonr_int} = {xor_result}")
                
                # 4. Respond: true if even, false otherwise
                is_even = (xor_result % 2 == 0)
                
                # DEBUG: Output final authorization value
                print(f"[DEBUG] Step 4 - Is even? {is_even}. Sending response.")
                
                # Send HTTP response
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                
                response_data = {"authorization": is_even}
                self.wfile.write(json.dumps(response_data).encode('utf-8'))
                
            except Exception as e:
                self.send_response(400)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"error": str(e)}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

def run_server(port=8000):
    server_address = ('', port)
    httpd = HTTPServer(server_address, SimpleRESTHandler)
    print(f"Starting simple REST API server on port {port}...")
    httpd.serve_forever()

if __name__ == '__main__':
    run_server()
