#!/usr/bin/env ruby
# From https://github.com/jasongill/idrac-kvm
# Jason Gill <jasongill@gmail.com>

# Get the required gems with:
# sudo gem install rest-client net-ssh-gateway slop

require 'rubygems'
require 'rest_client'
require 'net/ssh/gateway'
require 'slop'

def cyantext(string)
  puts "\033[0;36m -- " + string + "\033[0m"
end

def redtext(string)
  puts "\033[0;31m !! " + string + "\033[0m"
end

begin
  opts = Slop.parse do
    banner "Usage: #{$0} [options]"
    on :h, :help, 'Print this help message', :tail => true do
      puts help
      exit
    end
    on :b, :bounce, "Bounce server (optional)", :required => false, :optional => false
    on :l, :login, "Your username on bounce server (optional; defaults to #{ENV['USER']})", :default => ENV['USER'], :required => false, :optional => false
    on :s, :server, "Remote server IP (required)", :required => true, :optional => false
    on :u, :user, "Remote username (optional; defaults to root)", :default => "root", :required => false
    on :p, :password, "Remote password (required)", :required => true, :optional => false
  end

  bounceServer = opts[:bounce]
  bounceUser = opts[:login]
  remoteIP = opts[:server]
  remoteUser = opts[:user]
  remotePassword = opts[:password]

  serverPortHTTPS = 443
  serverPortVNC = 5900
  serverDomain = remoteIP

  if RUBY_PLATFORM.downcase.include?("linux")
    cyantext "Building Linux keycode hack"
    keycodec = Tempfile.new('keycodehack.c')
    keycodec.write(DATA.read)
    keycodec.close
    keycodeso = Tempfile.new('keycodehack.so')
    keycodeso.close
    system('gcc', "-o", keycodeso.path, "-xc", keycodec.path, "-shared", "-s", "-ldl", "-fPIC")
    ENV['LD_PRELOAD'] = keycodeso.path
  end

  if bounceServer && bounceUser
    serverPortHTTPS = 1443
    serverPortVNC = 15900
    serverDomain = "localhost"
    cyantext "Creating SSH tunnel via #{bounceUser}@#{bounceServer} for ports 443 and 5900"
    gateway = Net::SSH::Gateway.new(bounceServer, bounceUser)
    gateway.open(remoteIP, 443, 1443)
    gateway.open(remoteIP, 5900, 15900)
  end

  serverURL = "https://#{serverDomain}:#{serverPortHTTPS}"

  cyantext "Connecting to #{serverURL} and generating a session ID"
  loginsession = RestClient.post(
  serverURL + '/data/login',
  {:user => remoteUser, :password => remotePassword}
  )
  cookie = loginsession.cookies["_appwebSessionId_"].to_s

  cyantext "Logging in to #{serverURL} with session ID #{cookie}"
  redirectsession = RestClient.get(
  serverURL + '/index.html',
  {:cookies => {:_appwebSessionId_ => cookie}}
  )

  jnlpfile = Tempfile.new('idrac.jnlp')
  cyantext "Receiving KVM viewer JNLP file and writing to #{jnlpfile.path}"
  viewersession = RestClient.get(
  serverURL + '/viewer.jnlp(localhost@0@' + remoteIP + '@' + Time.now.to_i.to_s + ')',
  {:cookies => {:_appwebSessionId_ => cookie}}
  )

  sessionfiledata = viewersession.to_s
  sessionfiledata.gsub!(/port=5900/, "port=#{serverPortVNC}")
  sessionfiledata.gsub!(/#{serverDomain}:443/, "#{serverDomain}:#{serverPortHTTPS}")

  jnlpfile.write(sessionfiledata)
  jnlpfile.close

  cyantext "Starting Java viewer with tempfile #{jnlpfile.path}"
  system("javaws", "-wait", jnlpfile.path)

rescue Errno::ECONNREFUSED => error
  redtext "Error when attempting to open SSH tunnel: #{error.to_s}"
  redtext "Did you verify that you are able to make a key-based connection to the bounce server?"
  exit 2

rescue => error
  redtext "Error: #{error.to_s}"
  redtext "Try #{$0} --help for more information"
  exit 1

ensure
  unless cookie.nil?
    cyantext "Logging out of session #{cookie} to prevent future login errors"
    RestClient.get(
    serverURL + '/data/logout',
    {:cookies => {:_appwebSessionId_ => cookie}}
    )
  end

  unless gateway.nil?
    cyantext "Stopping SSH tunnel connection via #{bounceServer}"
    gateway.shutdown!
  end

  keycodec.unlink unless keycodec.nil?
  keycodeso.unlink unless keycodeso.nil?
  jnlpfile.unlink unless jnlpfile.nil?

end

__END__
/*
 * Shared library hack to translate evdev keycodes to old style keycodes.
 */
#include <stdio.h>
#include <unistd.h>
#include <dlfcn.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>


static int (*real_XNextEvent)(Display *, XEvent *) = NULL;
static KeyCode (*real_XKeysymToKeycode)(Display *, KeySym) = NULL;
static KeySym (*sym_XKeycodeToKeysym)(Display *, KeyCode, int) = NULL;
static int hack_initialised = 0;

#define DEBUG 0

static int enabled = 1;

#ifdef DEBUG
static FILE *fd = NULL;
#endif

static void
hack_init(void)
{
  void *h;

  h = dlopen("libX11.so", RTLD_LAZY);
  if (h == NULL) {
    fprintf(stderr, "Unable to open libX11\n");
    _exit(1);
  }

  real_XNextEvent = dlsym(h, "XNextEvent");
  if (real_XNextEvent == NULL) {
    fprintf(stderr, "Unable to find symbol\n");
    _exit(1);
  }

  real_XKeysymToKeycode = dlsym(h, "XKeysymToKeycode");
  if (real_XKeysymToKeycode == NULL) {
    fprintf(stderr, "Unable to find symbol\n");
    _exit(1);
  }

  sym_XKeycodeToKeysym = dlsym(h, "XKeycodeToKeysym");
  if (sym_XKeycodeToKeysym == NULL) {
    fprintf(stderr, "Unable to find symbol\n");
    _exit(1);
  }

#ifdef DEBUG
  if (fd == NULL) {
    fd = fopen("/tmp/keycode-log", "a");
    if (fd == NULL)
      fprintf(stderr, "Unable to open key-log\n");
  }
#endif

  hack_initialised = 1;
}

int
XNextEvent(Display *display, XEvent *event)
{
  int r;
  int keycode_new;

  if (!hack_initialised)
    hack_init();

  r = real_XNextEvent(display, event);

  if (event->type == KeyPress || event->type == KeyRelease) {
    XKeyEvent *keyevent;
    KeySym keysym;

    keyevent = (XKeyEvent *)event;
#ifdef DEBUG
    fprintf(fd, "KeyEvent: %d\n", keyevent->keycode);
    fflush(fd);
#endif

    keysym = sym_XKeycodeToKeysym(display, keyevent->keycode, 0);
    keycode_new = keyevent->keycode;
    switch (keysym) {
    case XK_Up:
      keycode_new = 98;
      break;
    case XK_Down:
      keycode_new = 104;
      break;
    case XK_Left:
      keycode_new = 100;
      break;
    case XK_Right:
      keycode_new = 102;
      break;
    case XK_Print:
      keycode_new = 111;
      break;
    case XK_Num_Lock:
      if (event->type == KeyPress) {
        enabled = ( enabled == 1 ? 0 : 1 );
#ifdef DEBUG
        fprintf(fd, "Toggle enabled to %d\n", enabled);
        fflush(fd);
#endif
      }
      break;
    }

    if (enabled == 1) 
      keyevent->keycode = keycode_new;
  }

  return r;
}

#ifdef DEBUG
KeyCode
XKeysymToKeycode(Display *display, KeySym keysym)
{
  KeyCode keycode;

  if (!hack_initialised)
    hack_init();

  keycode = real_XKeysymToKeycode(display, keysym);

  fprintf(fd, "XKeysymToKeycode: %d\n", keycode);
  fflush(fd);

  return keycode;
}
#endif