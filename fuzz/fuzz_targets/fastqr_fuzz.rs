#![no_main]

use libfuzzer_sys::fuzz_target;
use fast_qr::convert::ConvertError;
use fast_qr::qr::QRBuilder;
use fast_qr::Version;

fuzz_target!(|data: (u8, &[u8])| {
    let (version, bytes) = data;
    QRBuilder::new(bytes).version(Version::V02).build().unwrap();
});
