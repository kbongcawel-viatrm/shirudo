use std::{io::{Read, Write}, net::TcpListener};
fn main() {
    let listener = TcpListener::bind("0.0.0.0:8080").expect("bind");
    for mut stream in listener.incoming().flatten() {
        let mut request = [0u8; 1024];
        let _ = stream.read(&mut request);
        let body = r#"{"service":"rust-demo","ok":true}"#;
        let response = format!("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body);
        let _ = stream.write_all(response.as_bytes());
    }
}
