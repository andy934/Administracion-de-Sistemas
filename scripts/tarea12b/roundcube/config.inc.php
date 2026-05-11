<?php
// ═══════════════════════════════════════════════════════════════
// config.inc.php — Configuración institucional de Roundcube
// Práctica 12 Parte 2 — reprobados.com
// ═══════════════════════════════════════════════════════════════

// ── Identidad institucional ─────────────────────────────────────
$config['product_name']       = 'reprobados.com Webmail';
$config['username_domain']    = 'reprobados.com';
$config['mail_domain']        = 'reprobados.com';

// ── Servidor IMAP (mailserver en red Docker) ────────────────────
$config['default_host']       = 'tls://mailserver';
$config['default_port']       = 993;

// ── Servidor SMTP ───────────────────────────────────────────────
$config['smtp_server']        = 'tls://mailserver';
$config['smtp_port']          = 587;
$config['smtp_user']          = '%u';
$config['smtp_pass']          = '%p';

// ── TLS — aceptar certificados autofirmados ─────────────────────
$config['imap_conn_options']  = [
    'ssl' => ['verify_peer' => false, 'verify_peer_name' => false]
];
$config['smtp_conn_options']  = [
    'ssl' => ['verify_peer' => false, 'verify_peer_name' => false]
];

// ── Seguridad de sesión ─────────────────────────────────────────
$config['session_lifetime']   = 10;   // minutos de inactividad
$config['login_autocomplete'] = 0;    // sin autocompletado en login
$config['session_domain']     = '';

// ── Interfaz ────────────────────────────────────────────────────
$config['language']           = 'es_MX';
$config['skin']               = 'elastic';
$config['list_cols']          = ['subject', 'status', 'fromto', 'date', 'size', 'flag', 'attachment'];

// ── Adjuntos ─────────────────────────────────────────────────────
$config['max_message_size']   = '10M';

// ── Papelera y enviados ─────────────────────────────────────────
$config['sent_mbox']          = 'Sent';
$config['trash_mbox']         = 'Trash';
$config['drafts_mbox']        = 'Drafts';
$config['junk_mbox']          = 'Junk';
