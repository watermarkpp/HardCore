import java.nio.ByteBuffer;
import java.nio.channels.Pipe;
import java.nio.channels.Selector;

// Run by the Android build preflight, never by the game runtime.
class android_java_loopback_probe {
    public static void main(String[] args) throws Exception {
        for (int i = 0; i < 32; i++) {
            try (Selector selector = Selector.open()) {
                Pipe pipe = Pipe.open();
                try (Pipe.SourceChannel source = pipe.source(); Pipe.SinkChannel sink = pipe.sink()) {
                    sink.write(ByteBuffer.wrap(new byte[] { 73 }));
                    source.configureBlocking(false);
                    source.register(selector, java.nio.channels.SelectionKey.OP_READ);
                    if (selector.select(1000) != 1) throw new IllegalStateException("Pipe readiness failed");
                    ByteBuffer received = ByteBuffer.allocate(1);
                    if (source.read(received) != 1 || received.array()[0] != 73)
                        throw new IllegalStateException("Pipe transfer failed");
                }
            }
        }
        System.out.println("ANDROID_JAVA_LOOPBACK_PASS rounds=32 java=" + System.getProperty("java.version"));
    }
}
