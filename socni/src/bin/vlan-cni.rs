use anyhow::Result;
use tracing_subscriber::{FmtSubscriber, EnvFilter};
use tracing::{error, Level};
use vlan_cni::commands::run_cni;

fn main() -> Result<()> {
    // Set up tracing
    let subscriber = FmtSubscriber::builder()
        .with_env_filter(EnvFilter::from_default_env())
        .with_max_level(Level::INFO)
        .finish();
    
    let _ = tracing::subscriber::set_global_default(subscriber);
    
    // Run the CNI plugin
    if let Err(err) = run_cni() {
        error!("CNI plugin error: {}", err);
        
        // Output error in CNI format
        let error_msg = format!(
            r#"{{"cniVersion":"1.0.0","code":100,"msg":"{}","details":""}}"#,
            err.to_string().replace("\"", "\\\"")
        );
        eprintln!("{}", error_msg);
        std::process::exit(1);
    }
    
    Ok(())
}