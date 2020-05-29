import React,{Component} from 'react';
import './App.css';
import Amplify, {Analytics, AWSKinesisFirehoseProvider } from 'aws-amplify';
import config from './aws-exports.js'

Amplify.configure({
  Auth: {
    identityPoolId: config.aws_cognito_identity_pool_id,
    region: config.aws_project_region
  },
  Analytics: {
    AWSKinesisFirehose: {
      region: config.aws_project_region
    }
  }
});

Analytics.addPluggable(new AWSKinesisFirehoseProvider());

class App extends Component{
	constructor(props){
		super(props);
		this.state = {
			coins : [
				{name: "Bitcoin", votes: 0},
				{name: "Ethereum", votes: 0},
				{name: "Dash", votes: 0},
        {name: "Bitconnect", votes: 0},
        {name: "OmiseGo", votes: 0},
        {name: "Tezos", votes: 0},
        {name: "Icon", votes: 0}
			]
		}
	}

	vote (i) {
		let newcoins = [...this.state.coins];
		newcoins[i].votes++;
		function swap(array, i, j) {
			var temp = array[i];
			array[i] = array[j];
			array[j] = temp;
		}
		this.setState({coins: newcoins});
    const now = new Date();

    // Send to Firehose
    let data = {
      id: now.getTime(),
      coin: newcoins[i].name
    }

    Analytics.record({
      data: data,
      streamName: config.aws_firehose_name
    }, 'AWSKinesisFirehose');
    
	}

	render(){
		return(
			<>
				<h1>Shill your coins!</h1>
				<div className="coins">
					{
						this.state.coins.map((lang, i) => 
							<div key={i} className="coin">
								<div className="voteCount">
									{lang.votes}
								</div>
								<div className="coinName">
									{lang.name}
								</div>
								<button onClick={this.vote.bind(this, i)}>Click to shill</button>
							</div>
						)
					}
				</div>
			</>
		);
	}
}
export default App;