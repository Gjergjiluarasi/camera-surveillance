# --- Step 8: X11 Forwarding Configuration ---
echo "Configuring SSH Server for X11 Forwarding..."
sudo tee /etc/ssh/sshd_config.d/90-x11-forwarding.conf > /dev/null <<'EOF'
X11Forwarding yes
X11UseLocalhost yes
EOF
sudo sshd -t
sudo systemctl reload ssh
